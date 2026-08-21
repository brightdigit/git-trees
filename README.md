<img src="logo.svg" height="250" alt="git-trees logo">

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

```text
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
indexes, and HEADs. Every worktree is a direct child of the container root, so a
branch's `/` becomes a `-` in the directory name: `feature/x` checks out into
`feature-x/` while the branch keeps its real name.

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

**Convenience — one-line curl.** Same installer, downloaded and run in place.
It fetches the script *and* the agents template (skipping the template if that
path is already occupied, including a broken symlink):

```bash
curl -fsSL https://raw.githubusercontent.com/brightdigit/git-trees/main/install.sh | bash
```

A piped script receives no positional arguments, so set `TREES_DEST` to install
somewhere other than `~/.local/bin`:

```bash
TREES_DEST=/usr/local/bin curl -fsSL \
  https://raw.githubusercontent.com/brightdigit/git-trees/main/install.sh | bash
```

The installer uses `curl` or `wget`, whichever it finds, and verifies each
download is complete and non-empty before installing anything.

`main` is the stable release. A re-install from these URLs picks up the current
stable script and template.

Either way, make sure the destination is on your `PATH`:

```bash
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc ;; esac
```

`install.sh` warns if it isn't — either way you run it. Anything on `PATH`
named `git-trees` becomes `git trees`.

## Configuration

Every variable in [**Environment**](#environment) is optional. Add to
`~/.zshrc` (or `~/.bashrc`):

```zsh
export TREES_ORG=your-org
```

That's usually all you need — `TREES_HOST` defaults to `github.com` and
`TREES_AGENTS_TEMPLATE` defaults to `~/.config/git-trees/AGENTS.md`, which is
where `install.sh` and the curl install put the template.

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

> **`add` writes to the remote by default.** When pushing is enabled, upstream is
> set afterward via `track`. If the branch does not exist on `origin`, that runs
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

Branch names may contain `/`; the directory is the branch name with each `/`
replaced by `-`, since worktrees do not nest. That makes `feature/x` and
`feature-x` compete for one directory — whichever exists first keeps it, and
`add` refuses the other by name rather than inventing a variant. If the target
directory already exists for any other reason, `add` fails rather than inventing
a new name. If the branch already exists, `base` is ignored with a warning.

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

### `git trees rm <branch|path> [--apply]`

Removes a worktree and deletes its associated local branch when one exists. Accepts either a branch name or a worktree path.

By default (without `--apply`), reports what would be removed without making any changes. Pass `--apply` to perform the removal.

Worktree directories are removed via `TREES_RM_CMD` if configured, or `git worktree remove`. Local branches are deleted using `git branch -d` (falling back to `git branch -D` if needed).

A path target must be a worktree git already knows about; `rm` refuses any other
directory.

> **`TREES_RM_CMD` removes git's safety net.** `git worktree remove` refuses a
> worktree that has uncommitted changes or untracked files. A custom command such
> as `rm -rf` receives only the path and makes no such check, so `rm --apply` and
> `clean --apply` will destroy uncommitted work without warning. Set it only if
> you want `git worktree remove --force` semantics deliberately.


### `git trees clean [--merged|--gone] [--apply]`

Reports or removes stale worktrees and branches.

Selectors:
- `--gone`: branches whose upstream remote branch was deleted (`[gone]`)
- `--merged`: branches merged into the default branch. Automatically detects direct merges, rebased/cherry-picked commits, and squash-merged PRs while leaving fresh 0-commit branches intact.

Passing neither selector runs both `--gone` and `--merged`.

By default (without `--apply`), `clean` operates in dry-run mode and prints matching branches/worktrees without deleting them. Pass `--apply` to execute removals. Worktree directories are removed via `TREES_RM_CMD` if set (defaulting to `git worktree remove`) — see the warning above — and branches are deleted using `git branch -d` (falling back to `git branch -D` for gone/squash-merged branches).

`clean --apply` keeps going when an individual removal fails, reporting each one
on stderr, and exits nonzero if any of them did.



## Removing worktrees

`git-trees` provides `rm` and `clean` for removing worktrees and branches:

```bash
git trees rm feature-x --apply            # remove a single worktree and its branch
git trees clean --apply                   # remove merged and gone branches/worktrees
```

Both subcommands default to dry-run mode (report only) unless `--apply` is passed.
Both also delete unmerged work once `--apply` is given — `-d` escalates to `-D`.
If you have set `TREES_RM_CMD`, read the warning under [`git trees
rm`](#git-trees-rm-branchpath---apply) first: it removes git's check for
uncommitted changes.

Alternatively, you can use plain git:

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
| `TREES_NO_PUSH` | *(unset)* | Any non-empty value: `add`/`track` never create a branch on `origin` |
| `TREES_RM_CMD` | *(unset)* | Custom command for worktree directory removal (defaults to `git worktree remove`). Bypasses git's uncommitted-work check — see [`git trees rm`](#git-trees-rm-branchpath---apply) |
| `TREES_DEST` | `~/.local/bin` | Install destination for `install.sh`; the only way to choose one when piping the installer |

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

- `list` spawns several processes per branch — fine for dozens, slow for hundreds.

- `add` ignores `base` when the branch already exists rather than failing.
- Branch names beginning with `-` are unsupported: `add` parses them as options
  and reports `unknown option`. There is no `--` end-of-options marker.
- Bash-only (uses process substitution); not POSIX sh.

## Prior art

[grove](https://grove.safia.sh) covers similar ground with a compiled binary,
adjective-noun branch generation, `.groverc` bootstrap commands, and a `go`
subcommand that opens a subshell. Worth a look if you'd rather not maintain
shell.
