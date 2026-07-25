# AGENTS.md

Guidance for working on this repository.

## Memory & Corrections Convention

Before doing any work, read [`.claude/agent-notes.md`](.claude/agent-notes.md).
That file is the source of truth for user corrections and standing always/never
directives in this repo.

Maintain it as an append-only running log: when the user corrects you or gives
an always/never instruction, append one line proactively (do not wait to be
asked). Keep newest entries at the bottom, one line per entry. If a new
directive supersedes an older one, update or remove the stale line instead of
leaving both.

## What this is

`git-trees` is a single bash script installed as a git subcommand. It manages a
bare-repo + worktrees layout. Read `README.md` first for behavior; this file
covers constraints on changing it.

**This file is contributor guidance for `git-trees` itself** (`CLAUDE.md` is a
symlink to it). Do not confuse it with `AGENTS.md.template`, which is a
*product artifact*: `install.sh` copies it to `~/.config/git-trees/AGENTS.md`,
and `init` seeds it into the root of containers built with this tool, for an
entirely different audience. Nothing project-specific to this repo belongs in
the template.

## Constraints

**Single file.** `git-trees` must stay one self-contained script installable by
copying it onto `PATH`. Do not split into sourced libraries.

**Pure git.** No `gh`, `glab`, `jq`, or other external CLIs. `git`, coreutils,
and `awk` only. An earlier `pr` subcommand was removed specifically to
keep this property — do not reintroduce forge integration.

**Cannot cd the shell.** A git subcommand is a separate process. Any feature
needing to change the user's directory must instead print a path on stdout and
be wrapped by the optional shell function in the README. `--print-path` on `add`
is the established pattern: path to stdout, all other output to stderr.

**Worktrees do not nest.** Every worktree is a direct child of the container
root, so the directory name is the branch name with each `/` replaced by `-`
(`_slug`). The branch itself is never renamed — only the directory. The
consequence is that `feature/x` and `feature-x` compete for one directory;
`cmd_add` resolves this by refusing the second and naming the branch that owns
the directory (`_branch_at`). Do not "fix" that by inventing a suffixed variant:
a directory whose name the user cannot predict is worse than an error.

**Nothing destructive.** No subcommand removes a worktree or deletes a branch.
`clean` did, and was pulled before v1.0.0 ([#34](https://github.com/brightdigit/git-trees/issues/34)).
Anything that destroys user data must report by default and act only under an
explicit `--apply`, must use `git branch -d` and never `-D`, and must route
directory removal through a user-configurable command — see #34 for the full
contract before adding one.

**`track` only ever sets `origin/<branch>`.** Same remote, same name. There is
no flag for an arbitrary upstream, and `origin` is hardcoded throughout —
deliberately, since the layout assumes one remote. A user wanting something else
runs `git branch --set-upstream-to` themselves; `track` is idempotent and returns
early once *any* upstream is set, so it will not fight them. If this ever grows a
`--upstream <ref>` flag, `cmd_add` must pass it through — `add` calls `cmd_track`
unconditionally, and would otherwise overwrite what the user asked for.

## Two bugs that were found by testing — don't regress them

1. **`git worktree add -b <new> <base>` inherits the base ref's upstream.** A
   branch created from `origin/main` silently gets `origin/main` as its upstream
   and will push there. The new-branch path must pass `--no-track`, then let
   `cmd_track` set the correct upstream. Live in `cmd_add`; any change there
   needs a fresh test.

2. **`git branch --merged` flags branches with no commits of their own.** A
   branch just cut from `main` is reachable-from-`main` and looks merged. Any
   merged-branch pass must skip branches where
   `git rev-list --count origin/<def>..<br>` is 0. No code relies on this today —
   the `clean` command that did was removed — but the note stays, because losing
   it is how the bug comes back when `clean` returns (#34).

Both are counterintuitive and both were caught only by running against a real
repo.

## Testing

Run the suite:

```bash
tests/smoke.sh              # tests ./git-trees
tests/smoke.sh /path/to/git-trees
```

It builds its own fixtures under `mktemp -d` from `file://` remotes — no
network, no `jq`, nothing written outside the temp directory — and runs every
check to completion rather than stopping at the first failure. CI runs exactly
this, on `ubuntu-latest` and `macos-latest`
(`.github/workflows/ci.yml`), plus `bash -n` and
`shellcheck -s bash git-trees install.sh tests/smoke.sh`.

`tests/smoke.sh` is a test harness, not part of the tool. The single-file
constraint above governs `git-trees`; it does not forbid a test script.

What the suite covers:

- **help/dispatch** — `help`, `--help`, unknown command, and that the removed
  `clean` is *unrecognized* rather than merely unsuccessful
- **outside a repo** — `list` and `root` both exit nonzero
- **init** — happy path over `file://`; the gitdir pointer, bare store, seeded
  `AGENTS.md`, and `origin/*` refs it must produce; the container root having no
  work tree; refusal on an existing directory; **rollback when the post-clone
  fetch fails**, and that a retry then works; `--host`/`--dir` with a missing
  value exiting promptly rather than hanging
- **root** — printing the container, adopting a bare container by writing the
  `.git` pointer under the store's own name, rejecting a plain directory
- **root --agents** — seeds when absent; never overwrites a regular file; treats
  a **broken symlink** as occupied; no-ops without a template; keeps stdout to
  the path alone
- **add** — `.`, `..` and `'has space'` reported as bad branch names rather than
  directory collisions, and rejected before `Preparing worktree`; upstream
  exactly `origin/feature-x` for an existing remote branch and exactly
  `origin/brandnew` for a new one; directory collision; `--print-path` emitting
  only a path; argument errors; nonzero exit when `track`/push fails
- **add with a slash in the branch** — the directory is slugged (`feature/x` →
  `feature-x/`, `deep/new/branch` → `deep-new-branch/`) while the ref keeps its
  slash and tracks `origin/feature/x`; a second branch slugging to a taken
  directory is refused with the owning branch named
- **track** — idempotent on an already-tracked worktree; fails on a non-worktree
- **list** — text output, branches with no worktree shown as `(none)`,
  `--json` parsing, and a worktree whose path contains `\` and `"` round-tripping
  through `json.load`

Bug-shaped assertions carry a comment saying which bug they pin. Two are worth
knowing about:

- The missing-option-value checks are **bounded** (`run_bounded`). The
  regression is an infinite loop, so a plain assertion would hang the runner
  until the job timeout instead of failing. `timeout` is not installed on macOS,
  hence the background-PID and `kill -0` dance.
- `add brandnew` asserts the upstream is **exactly** `origin/brandnew`. The
  older `!= origin/main` form also passed on an empty or otherwise wrong
  upstream, which is the same bug wearing a different hat.

ShellCheck is not a safety net here — it passes clean on code containing both
the argument-parsing hang and the `_seed_agents` precedence bug. Linting is not
coverage.

Not covered: `init` against a real network host.

## Style

- `set -uo pipefail` at the top; deliberately not `-e`, since several checks
  rely on nonzero exits
- Functions prefixed `cmd_` are subcommands; `_`-prefixed are internal helpers
- Every subcommand validates its own args and prints usage to stderr on failure
- Comments explain *why*, particularly for the two bugs above — the `--no-track`
  and `rev-list --count` lines look removable without them
