# git-trees

A `git` subcommand for managing a **bare repo + worktrees** layout. Pure git — no
external CLI dependencies, no forge integration.

```
git trees init brightdigit/some-repo
cd some-repo
git trees add feature-x
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

### `git trees add <branch> [base] [--print-path] [--no-push]`

Creates a worktree, handling three cases:

| Situation | Behavior |
|---|---|
| Branch exists locally | Attach worktree to it |
| Branch exists on `origin` | Fetch, create with `--track` |
| Branch is new | Create from `base` (default `origin/<default>`) with `--no-track` |

> **`add` writes to the remote.** Upstream is always set afterward via `track`.
> If the branch does not exist on `origin`, that runs
> `git push -u origin HEAD` — **which creates the branch on the remote.** This
> is a reasonable default for parallel coding agents, which need an upstream to
> push to, but it means a local-feeling command fires CI, sends notifications,
> and publishes a branch name. Pass `--no-push` to skip it.

With `--no-push`, `add` sets the upstream when `origin/<branch>` already exists
and otherwise leaves it unset, printing the `git push -u origin HEAD` you can run
yourself. It still exits 0. Set `TREES_NO_PUSH` to any non-empty value to get
that behavior everywhere without passing the flag.

If the push or upstream setup fails, `add` exits nonzero (the worktree may still
exist). `--print-path` writes the path to stdout and everything else to stderr,
for shell wrappers.

Branch names must not contain `/` (rejected with a clear error). If the target
directory already exists, `add` fails rather than inventing a new name. If the
branch already exists, `base` is ignored with a warning.

### `git trees track [path] [--no-push]`

Idempotent. Ensures the branch in `path` (default `.`) has an upstream: sets it
to `origin/<branch>` if that exists remotely, otherwise runs
`git push -u origin HEAD`, **which creates the branch on `origin`**. Returns
immediately if an upstream is already configured.

`--no-push` (or a non-empty `TREES_NO_PUSH`) suppresses that push: the upstream
is left unset and the exact command to run is printed to stderr. Exit status
stays 0 — not setting an upstream is the requested outcome, not a failure.

Useful for repairing worktrees created before this tool. Note that pushing needs
forge credentials; without push rights, `track` fails unless you use `--no-push`.

### `git trees list [--json]` (alias `ls`)

One entry per branch with upstream, ahead/behind, last commit date, clean/dirty,
and path (relative to the project root). Includes branches with no worktree,
shown with path `(none)`. `--json` emits the same fields as an array.

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
| `TREES_AGENTS_TEMPLATE` | `~/.config/git-trees/AGENTS.md` | Seeded at the container root by `init` (and `root --agents`) |
| `TREES_NO_PUSH` | *(unset)* | Any non-empty value: `add`/`track` never create a branch on `origin` |

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

## Prior art

[grove](https://grove.safia.sh) covers similar ground with a compiled binary,
adjective-noun branch generation, `.groverc` bootstrap commands, and a `go`
subcommand that opens a subshell. Worth a look if you'd rather not maintain
shell.
