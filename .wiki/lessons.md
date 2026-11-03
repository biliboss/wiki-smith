# Lessons

One line per lesson from a real wiki-smith run: `- YYYY-MM-DD — <rule> — <why>`. Append only. When a lesson repeats or changes the procedure, move it into [SKILL.md](../SKILL.md), bump the [version](../CHANGELOG.md), and add `→ promoted in x.y.z` to the end of its line. Don't delete lines.

- 2026-11-03 — In `sh`, never put a `case` with `)` patterns inside `$( ... )`, and never a bracket of accented letters under `LC_ALL=C` — macOS `/bin/sh` rejects the first, and the second splits UTF-8 letters into bytes (found porting the scripts). → promoted in 0.1.0 (scripts)
- 2026-11-03 — Compare a port with the original on a real wiki and on a deliberately broken copy, sorted — file listing order differs between tools, so unsorted output looks like a mismatch. → promoted in 0.1.0 (lint.py sorts its output)
