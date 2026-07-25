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
- Branch names with `/` are supported and slug to `-` in the directory name; do not restore the old outright rejection (supersedes closed issues #4 and #8).
- User-facing docs (README, CHANGELOG) must not mention features that never shipped; 1.0.0 is the first release, so there is no prior version to reference. Rationale for removals belongs in AGENTS.md or the issue tracker.
