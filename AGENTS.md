# AGENTS.md

Guidance for working on this repository.

## What this is

`git-trees` is a single bash script installed as a git subcommand. It manages a
bare-repo + worktrees layout. Read `README.md` first for behavior; this file
covers constraints on changing it.

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

**Report before destroy.** `clean` defaults to reporting. Destructive work
happens only under `--apply`. Use `git branch -d`, never `-D`; when it fails,
print the `-D` command for the user rather than running it.

## Two bugs that were found by testing — don't regress them

1. **`git worktree add -b <new> <base>` inherits the base ref's upstream.** A
   branch created from `origin/main` silently gets `origin/main` as its upstream
   and will push there. The new-branch path must pass `--no-track`, then let
   `cmd_track` set the correct upstream.

2. **`git branch --merged` flags branches with no commits of their own.** A
   branch just cut from `main` is reachable-from-`main` and looks merged. The
   merged pass must skip branches where
   `git rev-list --count origin/<def>..<br>` is 0.

Both are counterintuitive and both were caught only by running against a real
repo. Any change touching `add` or `clean --merged` needs a fresh test.

## Testing

No test framework. Verify by building a throwaway repo pair:

```bash
rm -rf /tmp/tt && mkdir -p /tmp/tt/origin && cd /tmp/tt/origin
git init -q -b main . && git config user.email t@t && git config user.name t
echo hi > a.txt && git add . && git commit -qm init
git branch feature/x

cd /tmp/tt && git clone -q --bare /tmp/tt/origin proj/trees-bare.git
echo "gitdir: ./trees-bare.git" > proj/.git
cd proj
git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git config user.email t@t && git config user.name t
git fetch -q origin && git remote set-head origin --auto >/dev/null
```

Then exercise the paths. Things worth checking after any change:

- `add feature/x` — remote branch exists; upstream must be `origin/feature/x`
- `add brandnew` — no remote branch; upstream must be `origin/brandnew`, **not**
  `origin/main`
- `add x --print-path` — stdout must be *only* the path
- `list --json` — valid JSON, includes branches with no worktree
- `clean` — a freshly cut branch must not appear under "merged"
- `git trees` outside a repo — clean error, nonzero exit

Also run `bash -n git-trees` for syntax and `shellcheck git-trees` if available.

`init` needs network and is not covered by the above.

## Style

- `set -uo pipefail` at the top; deliberately not `-e`, since several checks
  rely on nonzero exits
- Functions prefixed `cmd_` are subcommands; `_`-prefixed are internal helpers
- Every subcommand validates its own args and prints usage to stderr on failure
- Comments explain *why*, particularly for the two bugs above — the `--no-track`
  and `rev-list --count` lines look removable without them
