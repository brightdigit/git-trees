# git-trees bash completion
#
# Source from ~/.bashrc (after bash-completion), or drop into a
# bash-completion completions directory as `git-trees`.
#
# The function name is not arbitrary: bash-completion's git driver dispatches
# `git <cmd>` to `_git_<cmd>` with dashes turned into underscores, so
# `git trees` lands on `_git_trees`. The standalone `git-trees` binary is wired
# up separately at the bottom of this file.

# SC2207 disabled file-wide: its suggested fix is `mapfile`, which is bash 4+,
# and this repo targets bash 3.2 (macOS system bash). The `COMPREPLY=( $(...) )`
# word-splitting idiom is the portable form and is what bash-completion itself
# uses.
# shellcheck disable=SC2207

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
# Every git call is silenced and short-circuited so completing outside a
# repository (or in a broken one) yields an empty list rather than an error in
# the prompt.
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

# The shared body. $1 is the index of the `git-trees` word itself in COMP_WORDS,
# which differs between `git trees …` (1) and `git-trees …` (0).
__git_trees_complete() {
  local base="$1" cur prev sub i
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # First non-flag word after the command name is the subcommand.
  sub=''
  i=$((base + 1))
  while [ "$i" -lt "$COMP_CWORD" ]; do
    case "${COMP_WORDS[i]}" in
      -*) ;;
      *) sub="${COMP_WORDS[i]}"; break ;;
    esac
    i=$((i + 1))
  done

  if [ -z "$sub" ]; then
    COMPREPLY=( $(compgen -W "$__git_trees_commands" -- "$cur") )
    return 0
  fi

  # --host and --dir take a value; offering flags there would be wrong.
  case "$prev" in
    --host) COMPREPLY=(); return 0 ;;
    --dir)  COMPREPLY=( $(compgen -d -- "$cur") ); return 0 ;;
  esac

  local flags
  flags=$(__git_trees_flags "$sub")

  if [ "${cur:0:1}" = "-" ]; then
    COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
    return 0
  fi

  # Positional argument. `init` takes an org/repo or URL we cannot enumerate.
  case "$sub" in
    rm)          COMPREPLY=( $(compgen -W "$(__git_trees_targets)" -- "$cur") ) ;;
    add)         COMPREPLY=( $(compgen -W "$(__git_trees_targets)" -- "$cur") ) ;;
    sync)        COMPREPLY=( $(compgen -W "$(__git_trees_worktrees)" -- "$cur") ) ;;
    root|track)  COMPREPLY=( $(compgen -d -- "$cur") ) ;;
    *)           COMPREPLY=( $(compgen -W "$flags" -- "$cur") ) ;;
  esac
  return 0
}

# bash-completion's git driver calls this with COMP_WORDS[0]="git",
# COMP_WORDS[1]="trees".
_git_trees() { __git_trees_complete 1; }

# Direct invocation as `git-trees`.
_git_trees_standalone() { __git_trees_complete 0; }
complete -F _git_trees_standalone git-trees
