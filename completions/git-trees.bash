# git-trees bash completion
#
# Source from ~/.bashrc (after bash-completion), or from ~/.zshrc when using
# Homebrew's git completion (a bash wrapper). Drop into a bash-completion
# completions directory as `git-trees`.
#
# The function name is not arbitrary: git's completion dispatches `git <cmd>`
# to `_git_<cmd>` with dashes turned into underscores, so `git trees` lands on
# `_git_trees`. That path is shared by bash-completion and by Homebrew's zsh
# `_git` wrapper — both expect this function to speak the git-completion API
# (`$cur` / `$words` / `__gitcomp`), not raw `compgen`/`COMPREPLY`. Using
# `compgen` under the zsh wrapper leaves `_ret=1` and falls through to path
# completion.
#
# The standalone `git-trees` binary is wired up separately at the bottom.

# Commands and per-subcommand flags live in one place so the two entry points
# (`git trees` and `git-trees`) cannot drift apart.
__git_trees_commands='init root add track list ls rm clean sync prune help'

__git_trees_flags() { # __git_trees_flags <subcommand>
  case "$1" in
    init)  echo '--host --dir' ;;
    root)  echo '--agents' ;;
    add)   echo '--print-path --no-push' ;;
    track) echo '--no-push' ;;
    list|ls) echo '--json' ;;
    rm)    echo '--apply' ;;
    clean) echo '--merged --gone --apply' ;;
    sync)  echo '--pull --ff-only --rebase' ;;
    prune) echo '--dry-run' ;;
    *)     echo '' ;;
  esac
}

# Worktree directory names, which are branch names slugged with `/`->`-`, so
# they routinely coincide with branch names — hence the awk dedupe. The bare
# container root is listed as a worktree by git but is not a removable target.
# Every git call is silenced so completing outside a repository is empty, not
# noisy.
__git_trees_worktrees() {
  git worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{
      sub(/^worktree /, "")
      n = split($0, p, "/")
      if (p[n] ~ /\.git$/) next
      if (!seen[p[n]]++) print p[n]
    }'
}

# Branch names plus worktree directory names — `rm` accepts either.
__git_trees_targets() {
  {
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    __git_trees_worktrees
  } | awk '!seen[$0]++'
}

# Prefer git-completion's __gitcomp when present (bash, and Homebrew's zsh
# wrapper which redefines it to compadd). Fall back to a COMPREPLY filler so
# tests and a bare `source` without git-completion still work.
__git_trees_comp() {
  if declare -F __gitcomp >/dev/null 2>&1; then
    __gitcomp "$@"
    return
  fi
  local list="$1" prefix="${2-}" cur_="${3-$cur}" suffix="${4- }"
  local c i=0
  local IFS=$' \t\n'
  COMPREPLY=()
  for c in $list; do
    if [ "$c" = "--" ]; then
      continue
    fi
    case "$c" in
      "$cur_"*)
        case "$c" in
          *=|*.) COMPREPLY[i++]="${prefix}$c" ;;
          *)     COMPREPLY[i++]="${prefix}$c${suffix}" ;;
        esac
        ;;
    esac
  done
}

__git_trees_comp_nl() {
  if declare -F __gitcomp_nl >/dev/null 2>&1; then
    __gitcomp_nl "$@"
    return
  fi
  local list="$1" prefix="${2-}" cur_="${3-$cur}" suffix="${4- }"
  local c i=0
  local IFS=$'\n'
  COMPREPLY=()
  for c in $list; do
    case "$c" in
      "$cur_"*) COMPREPLY[i++]="${prefix}$c${suffix}" ;;
    esac
  done
}

# Uses git-completion locals: cur, words, cword, prev, __git_cmd_idx.
# __git_cmd_idx is the index of `trees` (or `git-trees` for the standalone).
__git_trees_complete() {
  local sub i flags

  sub=
  i=$((__git_cmd_idx + 1))
  while [ "$i" -lt "$cword" ]; do
    case "${words[i]}" in
      -*) ;;
      *) sub="${words[i]}"; break ;;
    esac
    i=$((i + 1))
  done

  if [ -z "$sub" ]; then
    __git_trees_comp "$__git_trees_commands"
    return
  fi

  # --host and --dir take a value; offering flags there would be wrong.
  # Returning with no completer lets the shell fall back to default/path
  # completion for --dir (and for root/track positionals below).
  case "$prev" in
    --host) return ;;
    --dir)  return ;;
  esac

  flags=$(__git_trees_flags "$sub")

  case "$cur" in
    -*)
      __git_trees_comp "$flags"
      return
      ;;
  esac

  # Positional argument. `init` takes an org/repo or URL we cannot enumerate.
  case "$sub" in
    rm|add)      __git_trees_comp_nl "$(__git_trees_targets)" ;;
    sync)        __git_trees_comp_nl "$(__git_trees_worktrees)" ;;
    root|track)  return ;;
    *)           __git_trees_comp "$flags" ;;
  esac
}

# git's completion driver (bash, and Homebrew's zsh wrapper) calls this with
# cur/words/cword/prev/__git_cmd_idx already set. When invoked from tests via
# COMP_WORDS only, bootstrap those locals so the shared body can run.
_git_trees() {
  if [ -z "${words+set}" ] && [ -n "${COMP_WORDS+set}" ]; then
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD
    cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -gt 0 ]; then
      prev="${COMP_WORDS[COMP_CWORD-1]}"
    else
      prev=
    fi
    __git_cmd_idx=1
  fi
  __git_trees_complete
}

# Direct invocation as `git-trees` (COMP_WORDS[0]=git-trees).
_git_trees_standalone() {
  words=("${COMP_WORDS[@]}")
  cword=$COMP_CWORD
  cur="${COMP_WORDS[COMP_CWORD]}"
  if [ "$COMP_CWORD" -gt 0 ]; then
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  else
    prev=
  fi
  __git_cmd_idx=0
  __git_trees_complete
}

# `complete` is a bash builtin; under zsh it exists only after bashcompinit.
if [ -n "${BASH_VERSION-}" ] || declare -F complete >/dev/null 2>&1; then
  complete -F _git_trees_standalone git-trees
fi
