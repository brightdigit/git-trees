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
and `awk` only. Do not add forge integration.

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

**Nothing destructive without `--apply`.** `rm` and `clean` report by default and modify state only when `--apply` is explicitly passed. Local branch deletions use `git branch -d` (falling back to `-D` on `clean` once confirmed gone/merged, or on `rm` when `--apply` is passed), and worktree directory removals route through `TREES_RM_CMD` when configured (defaulting to `git worktree remove`).

**`TREES_RM_CMD` is the one place the safety net comes off.** `git worktree
remove` refuses a worktree with uncommitted changes or untracked files; a custom
command gets the path and nothing else. So a path target must be validated
against `git worktree list` before removal — `cmd_rm`'s path arm does this, and
without it `TREES_RM_CMD="rm -rf" git trees rm . --apply` would delete the
container root and the bare store. Keep the gate on worktree registration rather
than on the resolved branch: a detached-HEAD worktree legitimately has none.

**`clean --apply` reports partial failure.** Its loops continue past a failed
worktree removal or branch delete, but the exit status is nonzero if any failed,
matching `cmd_rm`. Do not turn that back into an unconditional `return 0` —
scripting `clean` depends on it.




**`track` only ever sets `origin/<branch>`.** Same remote, same name. There is
no flag for an arbitrary upstream, and `origin` is hardcoded throughout —
deliberately, since the layout assumes one remote. A user wanting something else
runs `git branch --set-upstream-to` themselves; `track` is idempotent and returns
early once *any* upstream is set, so it will not fight them. If this ever grows a
`--upstream <ref>` flag, `cmd_add` must pass it through — `add` calls `cmd_track`
unconditionally, and would otherwise overwrite what the user asked for.

## Git pitfall: new worktrees inherit upstream

`git worktree add -b <new> <base>` inherits the base ref's upstream. A branch
created from `origin/main` silently gets `origin/main` as its upstream and will
push there. The new-branch path must pass `--no-track`, then let `cmd_track` set
the correct upstream. Live in `cmd_add`; any change there needs a fresh test.

## Git pitfall: worktree paths are physical

`git worktree list` reports the *physical* path. Resolve any user-supplied
directory with `pwd -P`, never plain `pwd`, before comparing against it or
passing it to `_branch_at` — on macOS `$TMPDIR` lives under `/var`, a symlink to
`/private/var`, so the logical path matches nothing and a real worktree looks
unregistered. `cmd_rm`'s path arm depends on this; the smoke suite catches it
because its fixtures are built under `mktemp -d`.

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

- **help/dispatch** — `help`, `--help`, and unknown command
- **outside a repo** — `list` and `root` both exit nonzero
- **init** — happy path over `file://`; the gitdir pointer, bare store, seeded
  `AGENTS.md` content matching the template, and `origin/*` refs it must produce;
  the container root having no work tree; refusal on an existing directory;
  **rollback when the post-clone fetch fails**, and that a retry then works;
  `--host`/`--dir` with a missing value exiting promptly rather than hanging;
  missing template warns and writes no `AGENTS.md`
- **root** — printing the container, adopting a bare container by writing the
  `.git` pointer under the store's own name, rejecting a plain directory
- **root --agents** — seeds when absent; never overwrites a regular file; treats
  a **broken symlink** as occupied; warns and no-ops without a template; keeps
  stdout to the path alone
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
- **install.sh** — places the binary; seeds `~/.config/git-trees/AGENTS.md` from
  the template under a redirected `HOME`; does not overwrite an existing config
  file
- **rm** — dry run vs `--apply`, worktree removal by branch and by path (a
  slugged directory whose name is not a branch name, so the path arm is the one
  that runs), `-d` escalating to `-D` so an unmerged branch is still deleted
  under `--apply`, refusal of a directory that is not a registered worktree even
  with `TREES_RM_CMD` set, and custom `TREES_RM_CMD` routing
- **clean** — `--gone` identification and deletion, `--merged` identification
  across direct merges, rebased commits, and squash-merged PRs, zero-commit
  fresh branch preservation, dry run vs `--apply`, worktree directories actually
  gone after `--apply`, each selector run on its own, and custom `TREES_RM_CMD`
  routing

Two assertion shapes are easy to get wrong:

- The missing-option-value checks are **bounded** (`run_bounded`). An unbounded
  hang would sit until the job timeout instead of failing. `timeout` is not
  installed on macOS, hence the background-PID and `kill -0` dance.
- `add brandnew` asserts the upstream is **exactly** `origin/brandnew`. A looser
  check (for example `!= origin/main`) also passes on an empty or otherwise wrong
  upstream.

ShellCheck is not a safety net here — it can pass clean on an argument-parsing
hang or a wrong `_seed_agents` guard order. Linting is not coverage.

Not covered: `init` against a real network host.

## Style

- `set -uo pipefail` at the top; deliberately not `-e`, since several checks
  rely on nonzero exits
- Functions prefixed `cmd_` are subcommands; `_`-prefixed are internal helpers
- Every subcommand validates its own args and prints usage to stderr on failure
- Comments explain *why* — the `--no-track` line looks removable without one
