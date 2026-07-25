# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-07-25

First stable release. `git-trees` is a single bash script installed as a git
subcommand that manages a **bare repo + worktrees** layout: one shared object
store, one directory per branch, each independently checked out. Pure git — no
`gh`, no `jq`, no forge integration.

### Commands

| Command | Purpose |
|---|---|
| `init <org/repo\|repo\|url> [--host h] [--dir d]` | Create the container: bare clone, `.git` pointer, fetch refspec, `origin/HEAD` |
| `root [dir] [--agents]` | Print the container root; write the `.git` pointer if missing; optionally seed `AGENTS.md` |
| `add <branch> [base] [--print-path] [--no-push]` | Create a worktree and set its upstream |
| `track [path] [--no-push]` | Ensure a branch has an upstream; idempotent |
| `list [--json]` (alias `ls`) | Every branch, with or without a worktree |

### Layout

```
some-repo/
├── trees-bare.git/   bare store — shared objects and refs, never modified directly
├── .git              file containing "gitdir: ./trees-bare.git"
├── AGENTS.md         seeded from a template, if configured — container root only
└── feature-x/        one directory per branch, created by `add`
```

`init` creates the container; `add` creates working copies. The container root
itself has no files checked out.

### Configuration

All optional.

| Variable | Default | Purpose |
|---|---|---|
| `TREES_HOST` | `github.com` | Host for `init` URLs |
| `TREES_ORG` | *(unset)* | Default org; without it, bare repo names are rejected |
| `TREES_AGENTS_TEMPLATE` | `~/.config/git-trees/AGENTS.md` | Seeded at the container root |
| `TREES_NO_PUSH` | *(unset)* | Any non-empty value: never create a branch on `origin` |

### Requirements

Git, and **Bash — not POSIX `sh`**, because the script uses process
substitution. macOS's built-in `/bin/bash` 3.2 is sufficient; no Homebrew bash
is needed. `init` against a remote host needs network access and clone
credentials.

### Behavior worth knowing

- **`add` writes to the remote by default.** When the branch does not exist on
  `origin`, `add` (via `track`) runs `git push -u origin HEAD`, which creates it
  there. This suits the tool's use case — parallel coding agents that need an
  upstream — but it means a local-feeling command can fire CI and publish a
  branch name. Pass `--no-push`, or set `TREES_NO_PUSH`, to opt out: the upstream
  is left unset and the command to run is printed. ([#25])
- **Nothing here deletes.** No subcommand removes a worktree or a branch. Do it
  with git: `git worktree remove` + `git branch -d` + `git worktree prune`.
- **A branch's `/` becomes `-` in its directory name**, because worktrees are
  direct children of the container root and cannot nest. `feature/x` checks out
  into `feature-x/` and keeps its real name. That means `feature/x` and
  `feature-x` compete for one directory; whichever exists first keeps it, and
  `add` refuses the other by name.
- **`add` cannot `cd` your shell** — a git subcommand is a separate process. Use
  `--print-path` with the `trees()` wrapper in the README.

### Fixed

Everything below was found in the pre-1.0 review and fixed before the tag.

- `init --host` and `init --dir` with no value spun forever instead of erroring.
  `shift 2` fails when one argument remains and leaves `$1` in place, so the
  parse loop never terminated. ([#18])
- `init` printed `initialized …` and exited 0 even when the post-clone fetch or
  refspec configuration failed, leaving a container with no `origin/*` refs in
  which `add` could not resolve the default branch. It now rolls back, so a
  retry is not blocked by "already exists". ([#22])
- `list --json` emitted invalid JSON when a field contained a backslash — only
  `"` was escaped, and `\s` is not a valid JSON escape. Escaping is now done
  character by character, with control characters as `\u00XX`. ([#23])
- `add .` and `add ..` failed with "directory already exists" (because
  `$root/..` always does), and `add 'has space'` failed only after git printed
  `Preparing worktree…`. Branch names are validated with `git check-ref-format`
  up front. ([#31])
- `_seed_agents` guarded with `[ -e f ] || [ -L f ] && return 0`, which groups as
  `{ A || B; } && return 0` and yields status 1 when neither test holds. Both
  guards are explicit now, and a genuine write failure reports why. ([#32])

### Documentation

- The quickstart used to leave a new user in the container root, where
  `git status` fails with `fatal: this operation must be run in a work tree`. It
  now creates the first worktree, and the layout diagram distinguishes what
  `init` produces from what `add` produces. ([#20])
- "Requires bash 4+" was wrong — no bash-4-only features are used, and the
  likeliest interpreter on macOS is 3.2. ([#24])
- Added a Concepts primer (worktree, bare store, container, gitdir pointer,
  upstream) and a Prerequisites section. `AGENTS.md.template` now names
  `git trees add <name>` instead of only saying what not to do. ([#26])
- `install.sh --uninstall` ignored a custom prefix, so an install it had made
  could not be undone. It now takes `--uninstall [dir]`, warns when it finds
  nothing, and reports that it leaves `~/.config/git-trees/AGENTS.md` behind.
  The README documents what the curl path does *not* do. ([#29])
- Removed `lint.yml`, a comment-only file at the repo root that GitHub never ran
  and that would otherwise have shipped inside the tag. ([#33])

### Testing

Automated coverage moved to `tests/smoke.sh`, run by CI on `ubuntu-latest` and
`macos-latest` and by contributors with the same command. It builds `file://`
fixtures — no network, no `jq` — and covers `init` (including rollback on a
failed fetch), `root` and template seeding, `add` name validation and upstream
correctness, `track`, `list --json` escaping, and the `--no-push` paths.
Missing-value assertions are bounded so an infinite-loop regression fails fast
instead of hanging the runner. ([#27])

### Known limitations

- No `version` subcommand, so an installed script cannot report which release it
  is. Pin the curl URL to a tag if you need to know. ([#28])
- Removing stale worktrees and branches is manual; nothing here deletes.
- `list` spawns several processes per branch — fine for dozens, slow for
  hundreds.
- `add` ignores `base` when the branch already exists, rather than failing.
- Branch names beginning with `-` are unsupported; `add` parses them as options.
- Bash-only (process substitution); not POSIX `sh`.

[Unreleased]: https://github.com/brightdigit/git-trees/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/brightdigit/git-trees/releases/tag/v1.0.0
[#18]: https://github.com/brightdigit/git-trees/issues/18
[#20]: https://github.com/brightdigit/git-trees/issues/20
[#22]: https://github.com/brightdigit/git-trees/issues/22
[#23]: https://github.com/brightdigit/git-trees/issues/23
[#24]: https://github.com/brightdigit/git-trees/issues/24
[#25]: https://github.com/brightdigit/git-trees/issues/25
[#26]: https://github.com/brightdigit/git-trees/issues/26
[#27]: https://github.com/brightdigit/git-trees/issues/27
[#28]: https://github.com/brightdigit/git-trees/issues/28
[#29]: https://github.com/brightdigit/git-trees/issues/29
[#31]: https://github.com/brightdigit/git-trees/issues/31
[#32]: https://github.com/brightdigit/git-trees/issues/32
[#33]: https://github.com/brightdigit/git-trees/issues/33
