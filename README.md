> **Arquivado.** Este skill agora mora no plugin [biliboss/skills](https://github.com/biliboss/skills) (`skills/wiki-smith/`). Instale com `claude plugin marketplace add biliboss/skills` e `claude plugin install biliboss-skills@biliboss`.

# wiki-smith

An agent skill that **owns a repo's `.wiki/`**: the memory that agents read and maintain themselves. At the end of a session it looks at what happened and decides what to write, following the wiki's own rules. It is a sibling of [skill-smith](https://github.com/biliboss/skill-smith/tree/481f8239b04d59d4d017b945699788660750a3bb) (which writes skills; this writes wiki pages). The idea of an LLM that keeps a persistent wiki is [Karpathy's](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f); the credits are in [ATTRIBUTION.md](ATTRIBUTION.md).

| What the session had | What it does |
|---|---|
| A decision, delivery, change of course, incident or research | A daily note (one file per note) and the day's line in the inbox |
| A rule or lesson that holds beyond today | Also fixes the topic page: the rule as it holds now, no history |
| A new subject with several facets | A map of content `moc-<topic>.md` and pages `<topic>-<facet>.md`, with footers, in the index |
| Nothing worth recording | Says so and creates nothing |

Then always: the dates frontmatter, the regenerated day index, the lint, a commit of only its own files by path, and a sync when you ask. It also looks things up in the wiki cheaply (`rg` first, read only the matching section).

A repo can override names and language in `.wiki/wiki.config`, so one skill serves any repo with a `.wiki/`. A wiki that says "confirm first" gets a summary and a question before any edit.

## Install

```bash
npx skills add biliboss/wiki-smith -g --copy -a claude-code -y
```

This uses the [skills CLI](https://skills.sh). `-g` installs for your user, and `--copy` copies the files instead of linking them. Leave out `-a claude-code` to choose other agents. Then say "update the wiki", "note this in the wiki" or "create a moc for X". To configure a repo, copy [templates/wiki.config.example](templates/wiki.config.example) (or the [pt-BR preset](templates/wiki.config.pt-BR)) to `<repo>/.wiki/wiki.config`.

Needs `git`, a POSIX `sh` and `python3` (3.8+, stdlib only). It runs on macOS and Linux; no Node.

## The scripts

All take `-w <wiki dir>` and `-c <config>`. Plain POSIX `sh`, checked with `shellcheck`, plus one stdlib-only Python file.

| Script | What it does |
|---|---|
| `scripts/note.sh [-b] "Title"` | Creates today's note `<diary>/<day>/<HHMM>-<slug>.md` (UTC, slug rules, `-2` on collision), prints the path. Stdin is read only with `-b` (the body, after one blank line); without it the file is the title line and never waits on stdin |
| `scripts/day-index.sh` | Regenerates every day index from its notes folder. Limit: hand-written old-format notes in a day file are an error with `file:line`, not migrated |
| `scripts/dates.sh` | Writes `created`/`updated` from git (first/last commit; `updated` is today when the body changed since the last commit); idempotent |
| `scripts/lint.py` | Links, GitHub-style anchors (accents kept), index, footer, empty/orphan pages, diary, dates, History. `file:line: type: message`; exit 0 clean, 2 problems. Run as `python3 -I scripts/lint.py` |
| `scripts/sync.sh -m "msg" [-p] PATH...` | Commits only the given paths, in place or carried into a fresh `git worktree` from `origin/<main>` when the checkout is behind or shared; the generated day index is regenerated there, never carried; lints before committing and never pushes a red lint; with `-p`: fetch, rebase, `push HEAD:<main>`, fast-forward the checkout without touching others' edits, remove the worktree |
| `scripts/sync.sh -W` | Prints a fresh worktree from `origin/<main>` to edit shared files (index, inbox) in; then `sync.sh -m ... [-p] PATH...` from inside it |

## What's inside

- [SKILL.md](SKILL.md): the routing and the steps.
- [references/method.md](references/method.md): the full method. [references/config.md](references/config.md): every config key.
- [templates/](templates/): `page.md`, `moc.md`, `note.md`, and the config presets.
- [.wiki/](.wiki/README.md): wiki-smith's own memory, with its design decisions and lessons.
- [CHANGELOG.md](CHANGELOG.md): the changes, in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, with [SemVer](https://semver.org/spec/v2.0.0.html) versions.

## License

[MIT](LICENSE). Credits are in [ATTRIBUTION.md](ATTRIBUTION.md).
