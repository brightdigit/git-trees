# Agent notes (corrections & standing directives)

Read this file at the start of every session before doing work.
Source of truth for how to work in this repo beyond AGENTS.md.

Append one line per directive proactively (without being asked) whenever the
user makes a correction or gives an always/never instruction. Newest lines at
the bottom. One line per entry. When a directive supersedes an earlier one,
update or remove the stale line rather than leaving both.

## Log

- Never merge pull requests unless the user explicitly asks to merge.
- Do not change `AGENTS.md.template` for project-specific agent conventions; that file is for the installing developer.
- Branch names with `/` are supported and slug to `-` in the directory name; do not reject slash branches.
- User-facing docs (README, CHANGELOG) must not mention features that never shipped; 1.0.0 is the first release, so there is no prior version to reference.
- CHANGELOG follows GitHub release-notes format (`## What's Changed` + PR URLs), listing shipped features only — not Keep a Changelog / Unreleased / pre-1.0 fix archaeology. PR URLs remain even after the git history wipe.
- Do not mention previous code, removed subcommands, or pre-v1.0 archaeology anywhere in the tree (docs, comments, tests). Forward-looking constraints and current git-behavior rationale are fine.
- Do not remove an `init` container on agent-seeding failure; return nonzero and leave the directory.
- `main` is always the stable release; README curl install pins `main` (not version tags). Do not describe `main` as a development/moving target.
- `clean` supports `--gone` and `--merged` (detecting direct, rebased, and squash-merged PRs); `--older-than` is omitted.
