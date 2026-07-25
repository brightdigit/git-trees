# git-trees

A `git` subcommand for managing a **bare repo + worktrees** layout. Pure git — no
external CLI dependencies, no forge integration.

```
git trees init brightdigit/some-repo
cd some-repo
git trees add feature-x
git trees list
```

## Why

Working with multiple concurrent branches (particularly with parallel coding
agents, each pinned to its own worktree) is well served by git's worktree
support, but the built-in porcelain leaves gaps:

- `git worktree add -b` silently inherits the base ref's upstream, so a new
  branch ends up tracking `main` and pushes to the wrong place
- No single view of worktrees *and* branches that lack one
- Bare-clone setup for this layout is a four-command incantation

`git-trees` covers those. It's deliberately small and readable — one bash file
you can audit in a sitting.

## Layout

`git trees init` produces:

```
<repo>/
├── trees-bare.git/  bare git repo — never modified directly
├── .git             file containing "gitdir: ./trees-bare.git"
├── AGENTS.md        seeded from template, if configured — root only
└── <branch-name>/   one worktree per branch
```

Worktrees share a single object store but have independent working trees,
indexes, and HEADs. The worktree directory matches the branch name, so branch
names must not contain `/` — use dashes (`feature-x`, not `feature/x`).

## Install

```bash
curl -o ~/.local/bin/git-trees \
  https://raw.githubusercontent.com/brightdigit/git-trees/main/git-trees
chmod +x ~/.local/bin/git-trees
```

Or clone and run the installer (also seeds `~/.config/git-trees/AGENTS.md`):

```bash
git clone https://github.com/brightdigit/git-trees.git
cd git-trees && ./install.sh
```

Anything on `PATH` named `git-trees` becomes `git trees`. Requires bash 4+.

## Configuration

All three variables are optional. Add to `~/.zshrc` (or `~/.bashrc`):

```zsh
export TREES_ORG=your-org
```

That's usually all you need — `TREES_HOST` defaults to `github.com` and
`TREES_AGENTS_TEMPLATE` defaults to `~/.config/git-trees/AGENTS.md`, which is
where `install.sh` puts the template.

With `TREES_ORG` set, `git trees init my-repo` expands to `your-org/my-repo`.
Without it, bare repo names are rejected and you must pass `org/repo`.

Reload with `source ~/.zshrc`, then check with `echo $TREES_ORG`.

Note that these are shell-global. For a repo under a different org, pass
`org/repo` explicitly rather than changing the variable.

## Commands

### `git trees init <org/repo|repo|url> [--host h] [--dir d]`

Creates the bare clone, writes the `.git` pointer, fixes the fetch refspec (a
bare clone doesn't set up remote-tracking refs by default), and resolves
`origin/HEAD`.

Accepts:

| Form | Example |
|---|---|
| `org/repo` | `brightdigit/git-trees` → `https://github.com/…` |
| `repo` | requires `TREES_ORG` |
| HTTPS / SSH URL | `https://github.com/org/repo.git`, `git@github.com:org/repo.git` |

Directory defaults to the repo name; override with `--dir`. `--host` applies to
the shorthand forms only (ignored when a URL is given).

### `git trees root [dir] [--agents]`

Prints the project root (the directory that contains the bare store and
worktrees). If that root has no `.git` pointer yet but contains exactly one
bare `*.git` (e.g. a grove layout), writes `gitdir: ./<name>.git` first —
idempotent, does not rename the bare store — then prints the path on stdout.

Useful for adopting an existing worktree container without breaking other
tools that already know the `*.git` name.

`--agents` also seeds `AGENTS.md` at that root from `TREES_AGENTS_TEMPLATE`, for
containers that `init` did not create. Skipped if the file already exists or no
template is configured; the notice goes to stderr, so the path on stdout stays
clean for `$(git trees root)`.

### `git trees add <branch> [base] [--print-path]`

Creates a worktree, handling three cases:

| Situation | Behavior |
|---|---|
| Branch exists locally | Attach worktree to it |
| Branch exists on `origin` | Fetch, create with `--track` |
| Branch is new | Create from `base` (default `origin/<default>`) with `--no-track` |

Upstream is always set afterward via `track`; if that push/upstream setup fails,
`add` exits nonzero (the worktree may still exist). `--print-path` writes the
path to stdout and everything else to stderr, for shell wrappers.

Branch names must not contain `/` (rejected with a clear error). If the target
directory already exists, `add` fails rather than inventing a new name. If the
branch already exists, `base` is ignored with a warning.

### `git trees track [path]`

Idempotent. Ensures the branch in `path` (default `.`) has an upstream: sets it
to `origin/<branch>` if that exists remotely, otherwise `push -u`. Returns
immediately if an upstream is already configured.

Useful for repairing worktrees created before this tool.

### `git trees list [--json]` (alias `ls`)

One entry per branch with upstream, ahead/behind, last commit date, clean/dirty,
and path (relative to the project root). Includes branches with no worktree,
shown with path `(none)`. `--json` emits the same fields as an array.

## Removing worktrees

`git-trees` does not delete anything. Remove a worktree and its branch with git:

```bash
git worktree remove <path>
git branch -d <branch>          # -d refuses unmerged work; escalate to -D yourself
git worktree prune
```

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `TREES_HOST` | `github.com` | Host for `init` URLs |
| `TREES_ORG` | *(unset)* | Default org; if unset, bare repo names are rejected |
| `TREES_AGENTS_TEMPLATE` | `~/.config/git-trees/AGENTS.md` | Seeded at the container root by `init` (and `root --agents`) |

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

- Removing stale worktrees and branches is manual; nothing here deletes.
- `list` spawns several processes per branch — fine for dozens, slow for hundreds.
- `add` ignores `base` when the branch already exists rather than failing.
- Bash-only (uses process substitution); not POSIX sh.

## Prior art

[grove](https://grove.safia.sh) covers similar ground with a compiled binary,
adjective-noun branch generation, `.groverc` bootstrap commands, and a `go`
subcommand that opens a subshell. Worth a look if you'd rather not maintain
shell.
