#!/usr/bin/env bash
# tests/smoke.sh — end-to-end smoke tests for git-trees.
#
#   tests/smoke.sh [/path/to/git-trees]
#
# Runs the same suite CI runs. Everything happens in a throwaway directory built
# from `file://` fixtures: no network, no jq, no state outside $TMP.
#
# Style matches git-trees itself: `set -uo pipefail` but deliberately not `-e`,
# so every check runs and the summary lists all failures rather than the first.

set -uo pipefail

T="${1:-$(cd "$(dirname "$0")/.." && pwd)/git-trees}"
[ -f "$T" ] || { echo "smoke: no git-trees at $T" >&2; exit 1; }
T=$(cd "$(dirname "$T")" && pwd)/$(basename "$T")

REAL_GIT=$(command -v git) || { echo "smoke: git not on PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "smoke: python3 not on PATH" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

FAILED=0

section() { printf '\n== %s ==\n' "$1"; }
pass()    { printf '  ok    %s\n' "$1"; }
fail()    { printf '  FAIL  %s\n' "$1" >&2; FAILED=1; }

# `env -C` is GNU-only; macOS env has no such flag. Use a subshell instead.
# Called indirectly, as the command argument to the assert_* helpers — hence the
# suppressions. ShellCheck 0.9 reports that as SC2317 and 0.11 as SC2329, and CI
# runs whichever the runner image ships, so both codes are listed.
# shellcheck disable=SC2317,SC2329
in_dir() { local d="$1"; shift; ( cd "$d" && "$@" ); }

assert_eq() {   # assert_eq <label> <got> <want>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — got '$2', want '$3'"; fi
}

assert_contains() {   # assert_contains <label> <haystack> <needle>
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1 — output did not contain '$3': $2" ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1 — output unexpectedly contained '$3': $2" ;;
    *) pass "$1" ;;
  esac
}

assert_ok() {   # assert_ok <label> <cmd...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label — exit $?"; fi
}

assert_fail() { # assert_fail <label> <cmd...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$label — expected nonzero exit"; else pass "$label"; fi
}

# Run a command with a deadline. Prints nothing; returns 124 if it outlived the
# deadline, otherwise the command's own status. An unbounded hang would sit until
# the job timeout instead of failing. `timeout` is not installed on macOS.
run_bounded() { # run_bounded <seconds> <cmd...>
  local secs="$1"; shift
  "$@" >/dev/null 2>&1 &
  local pid=$! waited=0
  while [ "$waited" -lt "$((secs * 4))" ]; do
    kill -0 "$pid" 2>/dev/null || { wait "$pid"; return $?; }
    sleep 0.25
    waited=$((waited + 1))
  done
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 124
}

assert_no_hang() { # assert_no_hang <label> <cmd...>
  local label="$1"; shift
  local rc
  run_bounded 5 "$@"; rc=$?
  if [ "$rc" -eq 124 ]; then fail "$label — hung"
  elif [ "$rc" -eq 0 ]; then fail "$label — expected nonzero exit, got 0"
  else pass "$label"
  fi
}

# --- fixtures ----------------------------------------------------------------

# Isolate from the developer's ~/.gitconfig. Identity via env is enough for
# commits; GIT_CONFIG_GLOBAL keeps any incidental `git config --global` off disk
# outside $TMP.
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export GIT_AUTHOR_NAME=Smoke GIT_AUTHOR_EMAIL=smoke@example.com
export GIT_COMMITTER_NAME=Smoke GIT_COMMITTER_EMAIL=smoke@example.com

# An upstream with `main`, `feature-x`, and a pre-existing slash branch (as a
# real repo has), served over file://.
ORIGIN="$TMP/origin"
mkdir -p "$ORIGIN"
(
  cd "$ORIGIN" || exit 1
  git init -q -b main .
  git config user.email smoke@example.com
  git config user.name Smoke
  echo hi > a.txt
  git add . && git commit -qm init
  git branch feature-x
  git branch slug/one
) >/dev/null 2>&1

# The agents template, so seeding paths are exercised.
TEMPLATE="$TMP/AGENTS.md.template"
echo "seeded-agents-template" > "$TEMPLATE"
export TREES_AGENTS_TEMPLATE="$TEMPLATE"

# Build a container by hand (the layout `init` produces), for the tests that
# aren't about `init`.
new_container() { # new_container <name> -> prints path
  local d="$TMP/$1"
  mkdir -p "$d"
  git clone -q --bare "$ORIGIN" "$d/trees-bare.git"
  echo "gitdir: ./trees-bare.git" > "$d/.git"
  git -C "$d" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$d" config user.email smoke@example.com
  git -C "$d" config user.name Smoke
  git -C "$d" fetch -q origin
  git -C "$d" remote set-head origin --auto >/dev/null 2>&1
  echo "$d"
}

# --- help / dispatch ---------------------------------------------------------

section "help and dispatch"
assert_ok   "help exits 0" bash "$T" help
assert_ok   "--help exits 0" bash "$T" --help
assert_fail "unknown command exits nonzero" bash "$T" definitely-not-a-command
out=$(bash "$T" help 2>&1)
assert_contains "help lists add" "$out" "add <branch>"
assert_contains "help lists list" "$out" "list [--json]"
assert_contains "help lists rm" "$out" "rm <branch|path>"
assert_contains "help lists clean" "$out" "clean [--merged|--gone]"


section "outside a repo"
mkdir -p "$TMP/plain"
assert_fail "list outside a repo" in_dir "$TMP/plain" bash "$T" list
assert_fail "root outside a repo" in_dir "$TMP/plain" bash "$T" root

# --- init --------------------------------------------------------------------

section "init"
cd "$TMP" || exit 1

out=$(bash "$T" init "file://$ORIGIN" --dir init-ok 2>&1)
assert_contains "init reports the default branch" "$out" "initialized init-ok (default branch: main)"
assert_ok "init wrote the gitdir pointer" test -f "$TMP/init-ok/.git"
assert_ok "init created the bare store"    test -d "$TMP/init-ok/trees-bare.git"
assert_ok "init seeded AGENTS.md"          test -f "$TMP/init-ok/AGENTS.md"
assert_eq "init seeded content from the template" \
  "$(cat "$TMP/init-ok/AGENTS.md")" "seeded-agents-template"
# The refspec is what gives a bare clone its remote-tracking refs.
assert_ok "init set up origin/* refs" \
  git -C "$TMP/init-ok" show-ref --verify --quiet refs/remotes/origin/main
# A container root has no worktree — this is what the README quickstart warns about.
assert_fail "container root has no work tree" git -C "$TMP/init-ok" status

assert_fail "init into an existing directory" bash "$T" init "file://$ORIGIN" --dir init-ok

# Post-clone failure must not report success. A git shim on PATH fails only the
# `git -C <dir> fetch` that init runs after cloning.
SHIM="$TMP/shim"
mkdir -p "$SHIM"
cat > "$SHIM/git" <<EOSHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "-C" ] && [ "\${3:-}" = "fetch" ]; then exit 128; fi
exec "$REAL_GIT" "\$@"
EOSHIM
chmod +x "$SHIM/git"
out=$(PATH="$SHIM:$PATH" bash "$T" init "file://$ORIGIN" --dir init-broken 2>&1)
rc=$?
assert_eq "init exits nonzero when the post-clone fetch fails" "$rc" "1"
assert_not_contains "init does not claim success after a failed fetch" "$out" "initialized init-broken"
assert_ok "init removed the half-built container" test '!' -e "$TMP/init-broken"
# Rollback is what makes a retry possible; without it the user hits "already exists".
assert_ok "init can be retried after a failure" bash "$T" init "file://$ORIGIN" --dir init-broken

# Options that take a value must not spin forever when it is missing.
assert_no_hang "init --host with no value"           bash "$T" init --host
assert_no_hang "init --dir with no value"            bash "$T" init --dir
assert_no_hang "init org/repo --host with no value"  bash "$T" init org/repo --host
# The valid forms still work.
assert_ok "init --dir with a value" bash "$T" init "file://$ORIGIN" --dir init-flagged
assert_fail "init with no argument" bash "$T" init
assert_fail "init unknown option"   bash "$T" init "file://$ORIGIN" --nope

# Missing template: init still succeeds, warns on stderr, and writes no AGENTS.md.
err=$(mktemp)
out=$(env TREES_AGENTS_TEMPLATE="$TMP/no-such-template" \
  bash "$T" init "file://$ORIGIN" --dir init-notemplate 2>"$err")
rc=$?
assert_eq "init exits 0 without a template" "$rc" "0"
assert_contains "init still reports success without a template" "$out" \
  "initialized init-notemplate"
assert_contains "init warns on stderr when the template is missing" "$(cat "$err")" \
  "no agents template"
assert_ok "init without a template writes no AGENTS.md" \
  test '!' -e "$TMP/init-notemplate/AGENTS.md"

# --- root --------------------------------------------------------------------

section "root"
C=$(new_container root-c)
assert_eq "root prints the container" "$(cd "$C" && bash "$T" root)" "$C"

# A container with no .git pointer gets one written (the grove-adoption path).
NOPTR="$TMP/noptr"
mkdir -p "$NOPTR"
git clone -q --bare "$ORIGIN" "$NOPTR/custom-name.git"
assert_eq "root adopts a bare container" "$(bash "$T" root "$NOPTR" 2>/dev/null)" "$NOPTR"
assert_contains "root wrote the pointer at the bare store's own name" \
  "$(cat "$NOPTR/.git")" "gitdir: ./custom-name.git"

assert_fail "root on a plain directory"   bash "$T" root "$TMP/plain"
assert_fail "root on a missing directory" bash "$T" root "$TMP/no-such-dir"
assert_fail "root unknown option" bash "$T" root --nope

section "root --agents / template seeding"
# Absent → seeded.
S1=$(new_container seed-absent)
rm -f "$S1/AGENTS.md"
assert_ok "root --agents seeds AGENTS.md" bash "$T" root "$S1" --agents
assert_eq "seeded content came from the template" "$(cat "$S1/AGENTS.md")" "seeded-agents-template"

# Existing regular file → never overwritten.
S2=$(new_container seed-existing)
echo "MINE" > "$S2/AGENTS.md"
assert_ok "root --agents succeeds with a file present" bash "$T" root "$S2" --agents
assert_eq "an existing AGENTS.md is not overwritten" "$(cat "$S2/AGENTS.md")" "MINE"

# Broken symlink → occupied. `-e` is false here and `-L` is true, which is why
# the guard needs both tests.
S3=$(new_container seed-brokenlink)
rm -f "$S3/AGENTS.md"
ln -s "$TMP/definitely-absent" "$S3/AGENTS.md"
assert_ok "root --agents succeeds with a broken symlink present" bash "$T" root "$S3" --agents
assert_ok "a broken symlink counts as occupied" test -L "$S3/AGENTS.md"
assert_eq "the symlink was not replaced" "$(readlink "$S3/AGENTS.md")" "$TMP/definitely-absent"

# No template configured → no-op with a stderr warning, still succeeds.
S4=$(new_container seed-notemplate)
rm -f "$S4/AGENTS.md"
err=$(mktemp)
out=$(env TREES_AGENTS_TEMPLATE="$TMP/no-such-template" \
  bash "$T" root "$S4" --agents 2>"$err")
rc=$?
assert_eq "root --agents exits 0 without a template" "$rc" "0"
assert_eq "root --agents stdout is only the path without a template" "$out" "$S4"
assert_contains "root --agents warns on stderr when the template is missing" \
  "$(cat "$err")" "no agents template"
assert_ok "nothing was written without a template" test '!' -e "$S4/AGENTS.md"

# stdout stays clean for $(git trees root) even while seeding.
S5=$(new_container seed-stdout)
rm -f "$S5/AGENTS.md"
assert_eq "root --agents stdout is only the path" "$(bash "$T" root "$S5" --agents 2>/dev/null)" "$S5"

# --- add ---------------------------------------------------------------------

section "add"
C=$(new_container add-c)
cd "$C" || exit 1

# Invalid names must be reported as invalid names, not as directory collisions
# or unknown options. `$root/..` always exists, so without an early check
# `add ..` looks like a directory collision.
for bad in . ..; do
  out=$(bash "$T" add "$bad" 2>&1)
  assert_fail "add '$bad' fails" bash "$T" add "$bad"
  assert_not_contains "add '$bad' does not report a directory collision" "$out" "directory already exists"
done
out=$(bash "$T" add 'has space' 2>&1)
assert_fail "add 'has space' fails" bash "$T" add 'has space'
assert_not_contains "add 'has space' fails before git builds the worktree" "$out" "Preparing worktree"

# Branch exists on origin → upstream must be that branch.
assert_ok "add an existing remote branch" bash "$T" add feature-x
assert_eq "existing remote branch tracks itself" \
  "$(git -C feature-x rev-parse --abbrev-ref '@{upstream}')" "origin/feature-x"

# Brand-new branch → must NOT inherit the base ref's upstream. Assert the exact
# value: a looser check (for example `!= origin/main`) also passes on an empty
# or otherwise wrong upstream.
assert_ok "add a brand-new branch" bash "$T" add brandnew
assert_eq "new branch tracks its own remote, not the base" \
  "$(git -C brandnew rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" "origin/brandnew"

# Directory collision.
mkdir -p leftover-dir
out=$(bash "$T" add leftover-dir 2>&1)
assert_fail "add into an existing directory" bash "$T" add leftover-dir
assert_contains "collision message names the problem" "$out" "directory already exists"
rmdir leftover-dir

# --print-path: stdout is the path and nothing else.
p=$(bash "$T" add printed --print-path 2>/dev/null)
assert_ok "--print-path returned a directory" test -d "$p"
case $p in
  *$'\n'*) fail "--print-path stdout was multi-line" ;;
  *) pass "--print-path stdout is a single line" ;;
esac

# Re-adding an existing worktree is a no-op that still reports the path.
assert_eq "--print-path on an existing worktree returns it" \
  "$(bash "$T" add printed --print-path 2>/dev/null)" "$p"

assert_fail "add with no argument" bash "$T" add
assert_fail "add unknown option"   bash "$T" add x --nope
assert_fail "add too many arguments" bash "$T" add a b c

# --- add with a slash in the branch name -------------------------------------

# Worktrees are direct children of the container root, so a `/` cannot become a
# directory separator — it becomes `-`. Only the directory is slugged; the ref
# keeps its real name. Runs in its own container so `slug-one` cannot collide
# with a directory from another section.
section "add — slugged directories"
SL=$(new_container slug-c)
cd "$SL" || exit 1

assert_ok "add a slash branch that exists on origin" bash "$T" add slug/one
assert_ok "the directory is slugged" test -d slug-one
assert_eq "the branch keeps its slash" \
  "$(git -C slug-one symbolic-ref --short HEAD)" "slug/one"
assert_eq "a slash branch tracks its own remote branch" \
  "$(git -C slug-one rev-parse --abbrev-ref '@{upstream}')" "origin/slug/one"

# `slug/one` and `slug-one` slug to one directory. The second is refused rather
# than given an invented suffix, and the error names the branch that owns it.
out=$(bash "$T" add slug-one 2>&1)
assert_fail "a branch colliding with an existing slug is refused" bash "$T" add slug-one
assert_contains "the collision error names the owning branch" "$out" "slug/one"

# A new slash branch: every component slugged, and --no-track still applies, so
# it must not inherit the base ref's upstream.
assert_ok "add a brand-new slash branch" bash "$T" add deep/new/branch
assert_ok "every component is slugged" test -d deep-new-branch
assert_eq "a new slash branch tracks its own remote, not the base" \
  "$(git -C deep-new-branch rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" \
  "origin/deep/new/branch"

# `list` must agree with `add` about where a slash branch lives.
out=$(bash "$T" list 2>/dev/null)
assert_contains "list shows the slash branch" "$out" "slug/one"
assert_not_contains "list does not show it as having no worktree" \
  "$(bash "$T" list 2>/dev/null | grep 'slug/one')" "(none)"

cd "$C" || exit 1

# A failed upstream setup must fail `add` (the worktree may still exist).
BROKE=$(new_container add-nopush-remote)
cd "$BROKE" || exit 1
git remote set-url origin "$TMP/definitely-not-a-repo"
assert_fail "add exits nonzero when track/push fails" bash "$T" add willfail

# --- track -------------------------------------------------------------------

section "track"
cd "$C" || exit 1
assert_ok "track is idempotent on a tracked worktree" bash "$T" track feature-x
assert_eq "track left the upstream alone" \
  "$(git -C feature-x rev-parse --abbrev-ref '@{upstream}')" "origin/feature-x"
assert_fail "track on a non-worktree" bash "$T" track "$TMP"

# --- no-push -----------------------------------------------------------------

# `add` creates the branch on origin by default. --no-push opts out: the point
# is that nothing is written to the remote and the exit status is still 0,
# because leaving the upstream unset is the requested outcome, not a failure.
section "add --no-push"
NP=$(new_container nopush-c)
cd "$NP" || exit 1

out=$(bash "$T" add solo --no-push 2>&1)
assert_eq "add --no-push exits 0" "$?" "0"
assert_ok "--no-push created the worktree" test -d solo
assert_eq "--no-push checked out the branch" \
  "$(git -C solo symbolic-ref --short HEAD 2>/dev/null)" "solo"
assert_ok "add solo2 --no-push exits 0" bash "$T" add solo2 --no-push
assert_fail "--no-push did not create the branch on origin" \
  git ls-remote --exit-code --heads origin solo
assert_fail "--no-push left the upstream unset" \
  git -C solo rev-parse --abbrev-ref '@{upstream}'
assert_contains "--no-push prints the push command to run" "$out" "git push -u origin HEAD"

# When the remote branch already exists there is nothing to create, so the
# upstream must still be set.
assert_ok "add --no-push with an existing remote branch" bash "$T" add feature-x --no-push
assert_eq "--no-push still sets an existing upstream" \
  "$(git -C feature-x rev-parse --abbrev-ref '@{upstream}')" "origin/feature-x"

# The env var is the global form of the flag.
assert_ok "TREES_NO_PUSH exits 0" env TREES_NO_PUSH=1 bash "$T" add viaenv
assert_fail "TREES_NO_PUSH did not create the branch on origin" \
  git ls-remote --exit-code --heads origin viaenv

# --print-path must still print only the path.
p=$(bash "$T" add ppnp --no-push --print-path 2>/dev/null)
assert_ok "--no-push --print-path returned a directory" test -d "$p"

# The default is unchanged: a new branch IS created on the remote.
assert_ok "add without --no-push" bash "$T" add pushed
assert_ok "the default still creates the branch on origin" \
  git ls-remote --exit-code --heads origin pushed

# --- list --------------------------------------------------------------------

section "list"
cd "$C" || exit 1
assert_ok "list runs" bash "$T" list
out=$(bash "$T" list 2>/dev/null)
assert_contains "list includes a worktree branch" "$out" "feature-x"

# A branch with no worktree still appears, with path (none).
git branch orphaned origin/main >/dev/null 2>&1
out=$(bash "$T" list 2>/dev/null)
assert_contains "list includes branches with no worktree" "$out" "orphaned"
assert_contains "branches with no worktree show (none)" "$out" "(none)"

assert_ok "list --json parses" \
  in_dir "$C" bash -c "bash '$T' list --json | python3 -c 'import json,sys; json.load(sys.stdin)'"
assert_fail "list unknown option" bash "$T" list --nope

# JSON escaping: a path containing a backslash and a quote must round-trip.
# A bare `\s` is not a valid JSON escape, so a strict parser rejects the whole
# document if escaping is wrong.
JDIR="$TMP/json-esc"
mkdir -p "$JDIR"
JWT="$JDIR/back\\slash \"quoted\""
git worktree add -b jsonesc "$JWT" origin/main >/dev/null 2>&1
if [ -d "$JWT" ]; then
  got=$(bash "$T" list --json 2>/dev/null | python3 -c '
import json, sys
for e in json.load(sys.stdin):
    if e["branch"] == "jsonesc":
        print(e["path"])
        break
' 2>/dev/null)
  if [ -z "$got" ]; then
    fail "list --json with a backslash in the path"
  else
    pass "list --json with a backslash in the path parses"
    # The path git reports may be canonicalized (/tmp -> /private/tmp on macOS),
    # so compare the basename, which is what carries the awkward characters.
    assert_eq "the escaped path round-trips" "${got##*/}" 'back\slash "quoted"'
  fi
  git worktree remove --force "$JWT" >/dev/null 2>&1
  git branch -D jsonesc >/dev/null 2>&1
else
  fail "could not create a worktree with a backslash in its path"
fi

# --- install.sh --------------------------------------------------------------

section "install.sh"
REPO=$(dirname "$T")
IHOME="$TMP/install-home"
IDEST="$TMP/install-bin"
mkdir -p "$IHOME" "$IDEST"
out=$(HOME="$IHOME" bash "$REPO/install.sh" "$IDEST" 2>&1)
rc=$?
assert_eq "install.sh exits 0" "$rc" "0"
assert_ok "install.sh placed the binary" test -x "$IDEST/git-trees"
assert_ok "install.sh seeded the agents template" \
  test -f "$IHOME/.config/git-trees/AGENTS.md"
assert_eq "install.sh template matches AGENTS.md.template" \
  "$(cat "$IHOME/.config/git-trees/AGENTS.md")" \
  "$(cat "$REPO/AGENTS.md.template")"
echo CUSTOM > "$IHOME/.config/git-trees/AGENTS.md"
HOME="$IHOME" bash "$REPO/install.sh" "$IDEST" >/dev/null 2>&1
rc=$?
assert_eq "install.sh rerun exits 0" "$rc" "0"
assert_eq "install.sh does not overwrite an existing template" \
  "$(cat "$IHOME/.config/git-trees/AGENTS.md")" "CUSTOM"

# --- rm ----------------------------------------------------------------------

section "rm"
RM_C=$(new_container rm-c)
cd "$RM_C" || exit 1

assert_ok "create worktree to remove" bash "$T" add rm-target --no-push
assert_ok "worktree directory exists" test -d rm-target

out=$(bash "$T" rm rm-target 2>&1)
assert_ok "dry run leaves worktree intact" test -d rm-target
assert_contains "dry run reports plan" "$out" "Would remove worktree"
assert_contains "dry run instructs to use --apply" "$out" "(report only — pass --apply to execute)"

assert_ok "rm with --apply" bash "$T" rm rm-target --apply
assert_fail "worktree directory deleted" test -e rm-target
assert_fail "branch deleted" git show-ref --verify --quiet refs/heads/rm-target

# Unmerged branch: `-d` refuses it, so cmd_rm escalates to `-D` and both the
# worktree and the branch go under --apply. The commit is asserted: if it failed
# quietly the branch would be merged, `-d` would succeed, and the assertions
# below would pass without ever exercising the escalation.
assert_ok "create unmerged worktree" bash "$T" add rm-unmerged --no-push
echo "unmerged data" > rm-unmerged/unmerged.txt
assert_ok "stage unmerged work" in_dir rm-unmerged git add .
assert_ok "commit unmerged work" in_dir rm-unmerged git commit -qm "unmerged commit"

assert_ok "rm --apply removes worktree and unmerged branch" bash "$T" rm rm-unmerged --apply
assert_fail "worktree directory deleted for unmerged" test -e rm-unmerged
assert_fail "unmerged branch deleted" git show-ref --verify --quiet refs/heads/rm-unmerged


# Path target. cmd_rm resolves a branch name first, and every worktree above has
# a directory named after its branch, so the branch arm always wins. A slugged
# directory (`rm/by-path` -> `rm-by-path`) is not a branch name, so this is the
# only shape that reaches the path arm.
assert_ok "create slashed branch worktree" bash "$T" add rm/by-path --no-push
assert_ok "slugged directory exists" test -d rm-by-path
assert_ok "rm by path" bash "$T" rm "$RM_C/rm-by-path" --apply
assert_fail "worktree removed by path" test -e rm-by-path
assert_fail "branch removed by path" git show-ref --verify --quiet refs/heads/rm/by-path

# A plain directory is not a worktree and must be refused. Without the guard,
# TREES_RM_CMD would delete it outright — `rm .` would take out the container
# root and the bare store with it.
mkdir -p not-a-worktree
assert_fail "rm refuses a non-worktree directory" \
  env TREES_RM_CMD="rm -rf" bash "$T" rm not-a-worktree --apply
assert_ok "non-worktree directory left intact" test -d not-a-worktree
assert_ok "container root survives rm ." \
  env TREES_RM_CMD="rm -rf" bash -c "bash '$T' rm . --apply; test -d '$RM_C/trees-bare.git'"


# Custom TREES_RM_CMD
assert_ok "create worktree for custom TREES_RM_CMD" bash "$T" add rm-custom --no-push
assert_ok "rm with TREES_RM_CMD" env TREES_RM_CMD="rm -rf" bash "$T" rm rm-custom --apply
assert_fail "custom rm deleted directory" test -e rm-custom
assert_fail "custom rm deleted branch" git show-ref --verify --quiet refs/heads/rm-custom

assert_fail "rm with no argument" bash "$T" rm
assert_fail "rm with nonexistent target" bash "$T" rm nonexistent


# --- clean -------------------------------------------------------------------

# KEEP THIS SECTION LAST. Its fixtures mutate the shared $ORIGIN — deleting a
# branch, then merging, cherry-picking and squashing onto main. Every
# new_container clones $ORIGIN, so any section running after this one sees a
# different default-branch history than the ones before it.
section "clean"
CLEAN_C=$(new_container clean-c)
cd "$CLEAN_C" || exit 1

# Setup origin repo changes for clean testing. Each step is asserted: a silent
# failure here (a dirty $ORIGIN worktree, a checkout that did not land) would
# surface as a confusing failure in the assertions far below instead.
# 1. Gone upstream branch
assert_ok "add gone-branch" bash "$T" add gone-branch
assert_ok "delete gone-branch on origin" git -C "$ORIGIN" branch -D gone-branch

# 2. Direct merged branch
assert_ok "add merged-direct" bash "$T" add merged-direct
echo "direct change" > merged-direct/direct.txt
assert_ok "stage merged-direct" in_dir merged-direct git add .
assert_ok "commit merged-direct" in_dir merged-direct git commit -qm "direct commit"
assert_ok "push merged-direct" in_dir merged-direct git push -q -u origin merged-direct
assert_ok "merge merged-direct into origin main" \
  in_dir "$ORIGIN" git -c advice.detachedHead=false checkout -q main
assert_ok "merge merged-direct --no-ff" \
  in_dir "$ORIGIN" git merge -q merged-direct --no-ff -m "merge direct"
assert_ok "fetch after direct merge" git -C "$CLEAN_C" fetch -q origin

# 3. Rebase merged branch
assert_ok "add merged-rebase" bash "$T" add merged-rebase
echo "rebase change" > merged-rebase/rebase.txt
assert_ok "stage merged-rebase" in_dir merged-rebase git add .
assert_ok "commit merged-rebase" in_dir merged-rebase git commit -qm "rebase commit"
assert_ok "push merged-rebase" in_dir merged-rebase git push -q -u origin merged-rebase
assert_ok "checkout origin main for cherry-pick" in_dir "$ORIGIN" git checkout -q main
assert_ok "cherry-pick merged-rebase" in_dir "$ORIGIN" git cherry-pick merged-rebase

assert_ok "fetch after cherry-pick" git -C "$CLEAN_C" fetch -q origin

# 4. Squash merged branch
assert_ok "add merged-squash" bash "$T" add merged-squash
echo "squash change" > merged-squash/squash.txt
assert_ok "stage merged-squash" in_dir merged-squash git add .
assert_ok "commit merged-squash" in_dir merged-squash git commit -qm "squash commit"
assert_ok "push merged-squash" in_dir merged-squash git push -q -u origin merged-squash
assert_ok "checkout origin main for squash" in_dir "$ORIGIN" git checkout -q main
assert_ok "squash merge merged-squash" in_dir "$ORIGIN" git merge -q --squash merged-squash
assert_ok "commit the squash merge" in_dir "$ORIGIN" git commit -qm "squash merge commit"
assert_ok "fetch after squash merge" git -C "$CLEAN_C" fetch -q origin

# 5. Fresh 0-commit branch cut from main (MUST NOT be cleaned)
assert_ok "add fresh-branch" bash "$T" add fresh-branch --no-push



# Run dry run
out=$(bash "$T" clean 2>&1)
assert_contains "clean dry run reports gone branch" "$out" "gone-branch"
assert_contains "clean dry run reports direct merged" "$out" "merged-direct"
assert_contains "clean dry run reports rebase merged" "$out" "merged-rebase"
assert_contains "clean dry run reports squash merged" "$out" "merged-squash"
assert_not_contains "clean dry run preserves fresh 0-commit branch" "$out" "fresh-branch"
assert_contains "clean dry run reports report-only notice" "$out" "(report only — pass --apply to execute)"

# Each selector on its own. Passing neither runs both, so the default above
# cannot tell us that --gone and --merged actually gate their own sections.
out=$(bash "$T" clean --gone 2>&1)
assert_contains "clean --gone runs the gone section" "$out" "== branches with gone upstream =="
assert_not_contains "clean --gone skips the merged section" "$out" "== branches merged into"
assert_contains "clean --gone reports gone-branch" "$out" "gone-branch"
assert_not_contains "clean --gone omits merged branches" "$out" "merged-direct"

out=$(bash "$T" clean --merged 2>&1)
assert_contains "clean --merged runs the merged section" "$out" "== branches merged into"
assert_not_contains "clean --merged skips the gone section" "$out" "== branches with gone upstream =="
assert_contains "clean --merged reports merged-direct" "$out" "merged-direct"

# Apply clean. Assert the worktree directories too, not just the refs — a broken
# _remove_worktree call would leave every directory behind and still pass a
# refs-only check.
assert_ok "clean --apply" bash "$T" clean --apply
assert_fail "gone-branch deleted" git show-ref --verify --quiet refs/heads/gone-branch
assert_fail "gone-branch worktree removed" test -e gone-branch
assert_fail "merged-direct deleted" git show-ref --verify --quiet refs/heads/merged-direct
assert_fail "merged-direct worktree removed" test -e merged-direct
assert_fail "merged-rebase deleted" git show-ref --verify --quiet refs/heads/merged-rebase
assert_fail "merged-rebase worktree removed" test -e merged-rebase
assert_fail "merged-squash deleted" git show-ref --verify --quiet refs/heads/merged-squash
assert_fail "merged-squash worktree removed" test -e merged-squash
assert_ok "fresh-branch preserved after clean" git show-ref --verify --quiet refs/heads/fresh-branch
assert_ok "fresh-branch worktree preserved" test -d fresh-branch

# TREES_RM_CMD routing through clean, on a branch whose upstream goes away.
assert_ok "add clean-custom" bash "$T" add clean-custom
assert_ok "delete clean-custom on origin" git -C "$ORIGIN" branch -D clean-custom
assert_ok "clean --gone with TREES_RM_CMD" \
  env TREES_RM_CMD="rm -rf" bash "$T" clean --gone --apply
assert_fail "clean routed removal through TREES_RM_CMD" test -e clean-custom
assert_fail "clean deleted the gone branch" git show-ref --verify --quiet refs/heads/clean-custom

# Partial failure: remover fails, branch delete is skipped, exit is nonzero.
assert_ok "add clean-fail-a" bash "$T" add clean-fail-a
assert_ok "delete clean-fail-a on origin" git -C "$ORIGIN" branch -D clean-fail-a
assert_fail "clean --apply exits nonzero after a failed removal" \
  env TREES_RM_CMD="false" bash "$T" clean --gone --apply
assert_ok "branch kept when its worktree removal failed" \
  git show-ref --verify --quiet refs/heads/clean-fail-a
assert_ok "cleanup clean-fail-a after partial-failure case" \
  env TREES_RM_CMD="rm -rf" bash "$T" rm clean-fail-a --apply

# Cleanup fresh-branch
bash "$T" rm fresh-branch --apply >/dev/null 2>&1

# --- summary -----------------------------------------------------------------


cd "$TMP" || exit 1
echo
if [ "$FAILED" -eq 0 ]; then
  echo "smoke tests passed"
else
  echo "smoke tests FAILED" >&2
fi
exit "$FAILED"
