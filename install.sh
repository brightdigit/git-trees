#!/usr/bin/env bash
# install.sh — install git-trees onto PATH
#
#   ./install.sh                      install to ~/.local/bin
#   ./install.sh /usr/local/bin       install elsewhere

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config/git-trees"

DEST="${1:-$HOME/.local/bin}"

[ -f "$SRC/git-trees" ] || { echo "install.sh: git-trees not found in $SRC" >&2; exit 1; }

mkdir -p "$DEST" || exit 1
install -m 0755 "$SRC/git-trees" "$DEST/git-trees" || exit 1
echo "installed $DEST/git-trees"

# AGENTS.md template — README's curl path installs this too.
if [ -f "$SRC/AGENTS.md.template" ] && [ ! -f "$CFG/AGENTS.md" ]; then
  mkdir -p "$CFG"
  cp "$SRC/AGENTS.md.template" "$CFG/AGENTS.md"
  echo "installed $CFG/AGENTS.md (template; used by init or root --agents to seed the container root)"
fi

# Shell completions — same no-overwrite shape as the template above, so a user
# who edited an installed copy keeps it across reinstalls.
BASHCOMP="$CFG/completions/git-trees.bash"
ZSHCOMP="$CFG/completions/_git-trees"
if [ -f "$SRC/completions/git-trees.bash" ] && [ ! -f "$BASHCOMP" ]; then
  mkdir -p "$CFG/completions"
  cp "$SRC/completions/git-trees.bash" "$BASHCOMP"
  echo "installed $BASHCOMP (bash completion; source it from ~/.bashrc)"
fi
if [ -f "$SRC/completions/_git-trees" ] && [ ! -f "$ZSHCOMP" ]; then
  mkdir -p "$CFG/completions"
  cp "$SRC/completions/_git-trees" "$ZSHCOMP"
  echo "installed $ZSHCOMP (zsh completion; put its directory on fpath before compinit)"
fi

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "warning: $DEST is not on PATH — add it to use \`git trees\`" >&2 ;;
esac

echo
echo "try: git trees help"

if [ -f "$BASHCOMP" ] || [ -f "$ZSHCOMP" ]; then
  echo
  echo "to activate completions, add one of these to your shell rc:"
  [ -f "$BASHCOMP" ] && echo "  bash: source $BASHCOMP"
  [ -f "$ZSHCOMP" ]  && echo "  zsh:  fpath=($CFG/completions \$fpath)   # before compinit"
fi

if [ -z "${TREES_ORG:-}" ]; then
  echo
  echo "optional: set a default org so you can write 'git trees init <repo>'"
  echo "  echo 'export TREES_ORG=your-org' >> ~/.zshrc && source ~/.zshrc"
fi
