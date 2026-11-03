#!/bin/sh
# sync.sh - commit the given paths (and only them), optionally publish to origin/<MAIN_BRANCH>.
# Usage: sync.sh [-w WIKI_DIR] [-c CONFIG] -m "message" [-p] PATH...
#   -m  commit message (required; add the attribution lines your repo asks for, with a blank line)
#   -p  push: fetch, rebase onto origin/<main>, `git push origin HEAD:<main>`. Without -p nothing is
#       published. Use -p only when the user asked to sync.
#
# Commit in place when the checkout is on <main>, not behind origin/<main>, and has no changes outside
# PATH...  Otherwise (behind, another branch, or someone else's changes) work in a fresh `git worktree`
# from origin/<main>: carry the changes of PATH... there (git apply --3way), commit, and, with -p,
# rebase, push, then restore PATH... in the checkout and `merge --ff-only` it (never touching other
# people's modified files). Without -p the worktree is removed and the commit stays on a local branch
# wiki-sync/<time>, which is printed. Exit 0 ok, 1 on any failure (the checkout is left as it was).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
WIKI_ARG='' CFG_ARG='' msg='' push=0
while getopts 'w:c:m:p' o; do
  case $o in
    w) WIKI_ARG=$OPTARG ;;
    c) CFG_ARG=$OPTARG ;;
    m) msg=$OPTARG ;;
    p) push=1 ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if [ -z "$msg" ] || [ $# -eq 0 ]; then
  echo 'usage: sync.sh [-w DIR] [-c CONFIG] -m "message" [-p] PATH...' >&2
  exit 2
fi
export WIKI_ARG CFG_ARG
# shellcheck source=lib.sh
. "$here/lib.sh"
wiki_resolve

repo=$(git -C "$WIKI" rev-parse --show-toplevel)
main=$MAIN_BRANCH
orig=$(pwd)
cd "$repo"

# Paths relative to the repo root (they are given relative to the current directory or absolute).
: > "${TMPDIR:-/tmp}/wiki-smith-paths.$$"
paths_file=${TMPDIR:-/tmp}/wiki-smith-paths.$$
trap 'rm -f "$paths_file"' EXIT HUP INT TERM
for p in "$@"; do
  case $p in
    /*) abs=$p ;;
    *) abs=$orig/$p ;;
  esac
  d=$(dirname "$abs")
  b=$(basename "$abs")
  if [ -d "$d" ]; then abs=$(cd "$d" && pwd)/$b; fi
  rel=${abs#"$repo"/}
  if [ "$rel" = "$abs" ]; then
    echo "sync.sh: $p is outside the repository" >&2
    exit 1
  fi
  printf '%s\n' "$rel" >> "$paths_file"
done

has_remote=0
if git remote get-url origin >/dev/null 2>&1; then has_remote=1; fi
if [ "$has_remote" -eq 1 ]; then git fetch --prune --quiet origin; fi

# Does the checkout have changes outside PATH...?
in_paths() {
  while IFS= read -r p; do
    case $1 in
      "$p" | "$p"/*) return 0 ;;
    esac
  done < "$paths_file"
  return 1
}
others=''
git status --porcelain --untracked-files=all | sed 's/^...//' | sed 's/^"\(.*\)"$/\1/' > "$paths_file.status"
while IFS= read -r f; do
  if ! in_paths "$f"; then others="$others$f
"; fi
done < "$paths_file.status"
rm -f "$paths_file.status"
branch=$(git symbolic-ref --short -q HEAD || true)
behind=0
if [ "$has_remote" -eq 1 ]; then behind=$(git rev-list --count "HEAD..origin/$main" 2>/dev/null || echo 0); fi

add_paths() { while IFS= read -r p; do git add -A -- "$p"; done < "$paths_file"; }
commit_paths() {
  # Commit only the staged PATH... (nothing else staged by us): `--` limits the commit to the paths.
  set --
  while IFS= read -r p; do set -- "$@" "$p"; done < "$paths_file"
  if git diff --cached --quiet -- "$@"; then
    echo "sync.sh: nothing to commit in the given paths" >&2
    return 3
  fi
  git commit -q -m "$msg" -- "$@"
}

if [ "$branch" = "$main" ] && [ "$behind" -eq 0 ] && [ -z "$others" ]; then
  add_paths
  rc=0
  commit_paths || rc=$?
  if [ "$rc" -eq 3 ]; then exit 0; elif [ "$rc" -ne 0 ]; then exit 1; fi
  if [ "$push" -eq 1 ]; then git push -q origin "HEAD:$main"; fi
  git log -1 --format='committed %h %s'
  exit 0
fi

# Worktree mode.
if [ "$has_remote" -eq 0 ]; then
  echo "sync.sh: the checkout is not clean for an in-place commit and there is no origin to branch from" >&2
  exit 1
fi
wt=$(mktemp -d)
newbranch=wiki-sync/$(date -u +%Y%m%d%H%M%S)-$$
cleanup() { git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"; }
git worktree add -q -b "$newbranch" "$wt" "origin/$main"

fail() {
  echo "sync.sh: $1" >&2
  cleanup
  git branch -D "$newbranch" >/dev/null 2>&1 || true
  exit 1
}

# Carry the changes: tracked edits as a 3-way patch, untracked files by copy.
tracked_patch=$(mktemp)
set --
while IFS= read -r p; do set -- "$@" "$p"; done < "$paths_file"
git diff HEAD --binary -- "$@" > "$tracked_patch"
if [ -s "$tracked_patch" ]; then
  (cd "$wt" && git apply --3way --index "$tracked_patch") || { rm -f "$tracked_patch"; fail "could not apply your changes on origin/$main (conflict); resolve in the checkout and rerun"; }
fi
rm -f "$tracked_patch"
git ls-files --others --exclude-standard -- "$@" > "$paths_file.untracked"
while IFS= read -r f; do
  if [ -e "$wt/$f" ]; then fail "$f is new here but already exists on origin/$main"; fi
  mkdir -p "$wt/$(dirname "$f")"
  cp -p "$f" "$wt/$f"
done < "$paths_file.untracked"
rm -f "$paths_file.untracked"

(
  cd "$wt"
  set --
  while IFS= read -r p; do set -- "$@" "$p"; done < "$paths_file"
  for p in "$@"; do git add -A -- "$p"; done
  if git diff --cached --quiet; then exit 3; fi
  git commit -q -m "$msg"
) || rc=$?
if [ "${rc:-0}" -eq 3 ]; then
  cleanup
  git branch -D "$newbranch" >/dev/null 2>&1 || true
  echo "sync.sh: nothing to commit in the given paths" >&2
  exit 0
elif [ "${rc:-0}" -ne 0 ]; then
  fail "commit failed"
fi

if [ "$push" -eq 0 ]; then
  cleanup
  echo "committed on local branch $newbranch (not pushed); rerun with -p to publish the paths from the checkout"
  exit 0
fi

(
  cd "$wt"
  git fetch -q origin
  git rebase -q "origin/$main"
  git push -q origin "HEAD:$main"
) || fail "rebase or push failed; the commit is on branch $newbranch"

git fetch -q origin
# Our paths are now upstream: restore them in the checkout, then fast-forward it (only on <main>).
if [ "$branch" = "$main" ]; then
  while IFS= read -r p; do
    if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      git checkout -q HEAD -- "$p"
    fi
    git ls-files --others --exclude-standard -- "$p" | while IFS= read -r u; do rm -f "$u"; done
  done < "$paths_file"
  if git merge --ff-only -q "origin/$main"; then
    echo "pushed and fast-forwarded $main"
  else
    echo "pushed; $main could not be fast-forwarded (someone's local changes overlap): left as is" >&2
  fi
else
  echo "pushed to origin/$main; the checkout is on '$branch', left as is"
fi
cleanup
git branch -D "$newbranch" >/dev/null 2>&1 || true
git log -1 --format='origin/main at %h %s' "origin/$main" 2>/dev/null || true
