# git-trees

A `git` subcommand for managing a **bare repo + worktrees** layout. Pure git — no
external CLI dependencies, no forge integration.

```
git trees init brightdigit/some-repo
cd some-repo
git trees add feature/x
git trees list
git trees clean --older-than 30
```

## Why

Working with multiple concurrent branches (particularly with parallel coding
agents, each pinned to its own worktree) is well served by git's worktree
support, but the built-in porcelain leaves gaps:

- `git worktree add -b` silently inherits the base ref's upstream, so a new
  branch ends up tracking `main` and pushes to the wrong place
- No single view of worktrees *and* branches that lack one
- No cleanup for branches whose remote is gone
- Bare-clone setup for this layout is a four-command incantation

`git-trees` covers those. It's deliberately small and readable — one bash file
you can audit in a sitting.

## Layout

`git trees init` produces:

```
<repo>/
├── trees-bare.git/  bare git repo — never modified directly
├── .git             file containing "gitdir: ./trees-bare.git"
├── AGENTS.md        copied from template, if configured
└── <branch-name>/   one worktree per branch
```

Worktrees share a single object store but have independent working trees,
indexes, and HEADs. Branch names are slugified for directory names
(`feature/x` → `feature-x`).

## Install

```bash
curl -o ~/.local/bin/git-trees https://raw.githubusercontent.com/<you>/git-trees/main/git-trees
chmod +x ~/.local/bin/git-trees
```

Anything on `PATH` named `git-trees` becomes `git trees`. Requires bash 4+ and
`column` (both standard on macOS and most Linux).

## Commands

### `git trees init <org/repo|repo> [--host h] [--dir d]`

Creates the bare clone, writes the `.git` pointer, fixes the fetch refspec (a
bare clone doesn't set up remote-tracking refs by default), and resolves
`origin/HEAD`.

A bare repo name requires `TREES_ORG` to be set; otherwise pass `org/repo`.
Host defaults to `github.com`.

### `git trees add <branch> [base] [--print-path]`

Creates a worktree, handling three cases:

| Situation | Behavior |
|---|---|
| Branch exists locally | Attach worktree to it |
| Branch exists on `origin` | Fetch, create with `--track` |
| Branch is new | Create from `base` (default `origin/<default>`) with `--no-track` |

Upstream is always set afterward via `track`. `--print-path` writes the path to
stdout and everything else to stderr, for shell wrappers.

If the branch already exists, `base` is ignored with a warning.

### `git trees track [path]`

Idempotent. Ensures the branch in `path` (default `.`) has an upstream: sets it
to `origin/<branch>` if that exists remotely, otherwise `push -u`. Returns
immediately if an upstream is already configured.

Useful for repairing worktrees created before this tool.

### `git trees list [--json]` (alias `ls`)

Table of branch, upstream, ahead/behind, last commit date, clean/dirty, and
path. Includes branches with no worktree, shown with path `(none)`.

### `git trees clean [--older-than N] [--merged|--gone] [--apply]`

Reports by default; `--apply` executes. Three passes:

- **gone** — branches whose upstream is deleted (`[gone]`)
- **merged** — branches merged into the default branch, *excluding* those with
  no commits of their own (a branch freshly cut from `main` is technically
  merged but isn't finished work)
- **older-than** — worktrees whose directory mtime exceeds N days

`--gone` and `--merged` are mutually exclusive selectors; passing neither runs
both. Uses `git branch -d` (safe) and tells you when to escalate to `-D`. Never
removes the repo root or your current directory.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `TREES_HOST` | `github.com` | Host for `init` URLs |
| `TREES_ORG` | *(unset)* | Default org; if unset, bare repo names are rejected |
| `TREES_AGENTS_TEMPLATE` | `~/.config/git-trees/AGENTS.md` | Copied into each new worktree |

## Shell wrapper (optional)

A subcommand runs in its own process and cannot `cd` your shell. If you want
`add` to drop you in the new worktree:

```bash
trees() {
  case "$1" in
    add) shift; cd "$(git trees add "$@" --print-path)" ;;
    *)   git trees "$@" ;;
  esac
}
```

## Known limitations

- `--older-than` uses directory mtime, which build output touches. Last commit
  date would be a truer measure of staleness.
- `list` spawns several processes per branch — fine for dozens, slow for hundreds.
- `add` ignores `base` when the branch already exists rather than failing.
- Bash-only (uses process substitution); not POSIX sh.
- `init` assumes HTTPS remotes.

## Prior art

[grove](https://grove.safia.sh) covers similar ground with a compiled binary,
adjective-noun branch generation, `.groverc` bootstrap commands, and a `go`
subcommand that opens a subshell. Worth a look if you'd rather not maintain
shell.
