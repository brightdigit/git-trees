#!/usr/bin/env bash
# install.sh — install git-trees onto PATH
#
#   ./install.sh                 install to ~/.local/bin
#   ./install.sh /usr/local/bin  install elsewhere
#   ./install.sh --uninstall     remove

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/.local/bin}"

if [ "${1:-}" = "--uninstall" ]; then
  for d in "$HOME/.local/bin" /usr/local/bin; do
    if [ -e "$d/git-trees" ]; then
      rm -f "$d/git-trees" && echo "removed $d/git-trees"
    fi
  done
  exit 0
fi

[ -f "$SRC/git-trees" ] || { echo "install.sh: git-trees not found in $SRC" >&2; exit 1; }

mkdir -p "$DEST" || exit 1
install -m 0755 "$SRC/git-trees" "$DEST/git-trees" || exit 1
echo "installed $DEST/git-trees"

# AGENTS.md template
CFG="$HOME/.config/git-trees"
if [ -f "$SRC/AGENTS.md.template" ] && [ ! -f "$CFG/AGENTS.md" ]; then
  mkdir -p "$CFG"
  cp "$SRC/AGENTS.md.template" "$CFG/AGENTS.md"
  echo "installed $CFG/AGENTS.md (edit to taste; seeded at the container root)"
fi

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "warning: $DEST is not on PATH — add it to use \`git trees\`" >&2 ;;
esac

echo
echo "try: git trees help"
