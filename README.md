# git-trees

A `git` subcommand for managing a **bare repo + worktrees** layout. Pure git — no
external CLI dependencies, no forge integration.

```bash
git trees init brightdigit/some-repo   # creates the container
cd some-repo
git trees add main                     # first worktree — your files live here
cd main
```

`init` creates the *container*: a shared object store plus a `.git` pointer, and
nothing else. `add` creates a *working copy*. Between the two, the container root
has no files checked out and `git status` there reports
`fatal: this operation must be run in a work tree` — that is expected, not a
broken install.

From then on, one directory per branch:

```bash
git trees add feature-x   # sibling worktree, its own working copy
git trees list            # every branch, with or without a worktree
```

`add` prints the new path but cannot `cd` your shell — it runs in its own
process. The optional [`trees()` wrapper](#shell-wrapper-optional) below makes
`trees add feature-x` drop you straight into it.

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

## Concepts

New to `git worktree`? Five terms cover everything below.

- **Worktree** — a checked-out working copy: files on disk, its own index and
  its own `HEAD`. Plain git gives you one per clone; `git worktree` lets one repo
  have several, each on a different branch, all editable at once.
- **Bare store** (`trees-bare.git/`) — the repository's objects and refs with no
  working copy attached. Every worktree shares this one store, which is why
  adding a tenth worktree costs a checkout, not a tenth copy of your history.
  Never modify it directly.
- **Container** — the directory holding the bare store and all the worktrees. It
  is the thing `init` creates and what `git trees root` prints. It is *not*
  itself a checkout.
- **Gitdir pointer** (`.git`) — a one-line file reading
  `gitdir: ./trees-bare.git`. Without it, plain `git` commands run from the
  container root would walk up and find some unrelated parent repo, or nothing.
  With it, `git fetch` and friends work from the root even though no files are
  checked out there.
- **Upstream** — the remote branch a local branch pushes to and compares
  against (`origin/feature-x`). Setting it correctly on new branches is most of
  what this tool does — see the `git trees add` section under **Commands**.

`git-trees` is a thin layer that keeps this layout consistent. Everything it
does, you could do with `git worktree` by hand.

## Layout

`init` and `add` produce different things — the container first, working copies
after:

```
After `git trees init`:            After `git trees add feature-x`:

some-repo/                         some-repo/
├── trees-bare.git/                ├── trees-bare.git/
├── .git                           ├── .git
└── AGENTS.md                      ├── AGENTS.md
                                   └── feature-x/     ← your working copy
   no files checked out yet
```

- `trees-bare.git/` — the bare store; never modified directly
- `.git` — a file containing `gitdir: ./trees-bare.git`
- `AGENTS.md` — seeded from a template if one is configured; container root only
- `feature-x/` — one directory per branch, created by `add`, never by `init`

Worktrees share a single object store but have independent working trees,
indexes, and HEADs. The worktree directory matches the branch name, so branch
names must not contain `/` — use dashes (`feature-x`, not `feature/x`).

## Prerequisites

- **Git.**
- **Bash** — not POSIX `sh`; the script uses process substitution. macOS's
  built-in `/bin/bash` 3.2 is fine, as long as that is what `env bash` resolves
  to. No Homebrew bash needed.
- **Network access** for `init` against a remote host, and **forge credentials**
  for the clone. `add` and `track` also push by default, which needs push
  rights — see the `git trees add` section under **Commands**.
- Optionally, an **agents template** at `~/.config/git-trees/AGENTS.md`, which
  `./install.sh` puts there for you.

## Install

**Recommended — clone and run the installer.** This is the full install: it
places the script *and* seeds the agents template that
`TREES_AGENTS_TEMPLATE` defaults to.

```bash
git clone https://github.com/brightdigit/git-trees.git
cd git-trees && ./install.sh              # → ~/.local/bin
./install.sh /usr/local/bin               # or anywhere else
```

**Convenience — one-line curl.** Fetches only the script:

```bash
curl -o ~/.local/bin/git-trees \
  https://raw.githubusercontent.com/brightdigit/git-trees/main/git-trees
chmod +x ~/.local/bin/git-trees
```

Two things to know about this path. It does **not** create
`~/.config/git-trees/AGENTS.md`, so the documented default for
`TREES_AGENTS_TEMPLATE` points at a file you don't have — seeding is simply
skipped, which is harmless, but `init` will not write an `AGENTS.md`. And it
tracks `main`, which moves: what you get today is not necessarily what you got
last week. Use the installer if you want a known state.

Either way, make sure the destination is on your `PATH`:

```bash
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc ;; esac
```

`install.sh` warns if it isn't; the curl path cannot. Anything on `PATH` named
`git-trees` becomes `git trees`.

### Uninstall

```bash
./install.sh --uninstall              # clears ~/.local/bin and /usr/local/bin
./install.sh --uninstall /opt/bin     # or the prefix you installed to
```

Pass the same directory you installed to — without it, a custom-prefix install is
left behind. Uninstall does **not** remove `~/.config/git-trees/AGENTS.md`; it
says so, and you can delete it yourself.

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
