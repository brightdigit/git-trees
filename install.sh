#!/usr/bin/env bash
# install.sh — install git-trees onto PATH
#
#   ./install.sh                      install to ~/.local/bin
#   ./install.sh /usr/local/bin       install elsewhere
#   ./install.sh --uninstall          remove from the two default locations
#   ./install.sh --uninstall /opt/bin remove from the prefix you installed to

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config/git-trees"

if [ "${1:-}" = "--uninstall" ]; then
  # Honor the same DEST as install. Without an argument, sweep the two defaults;
  # a custom-prefix install would otherwise be left behind silently.
  if [ -n "${2:-}" ]; then
    set -- "$2"
  else
    set -- "$HOME/.local/bin" /usr/local/bin
  fi

  removed=0
  for d in "$@"; do
    if [ -e "$d/git-trees" ]; then
      if rm -f "$d/git-trees"; then
        echo "removed $d/git-trees"
        removed=1
      fi
    fi
  done

  if [ "$removed" -eq 0 ]; then
    echo "install.sh: no git-trees found in $*" >&2
    echo "  if you installed elsewhere, pass it: ./install.sh --uninstall <dir>" >&2
  fi

  if [ -e "$CFG/AGENTS.md" ]; then
    echo "left $CFG/AGENTS.md in place — remove it yourself if you want it gone"
  fi
  exit 0
fi

DEST="${1:-$HOME/.local/bin}"

[ -f "$SRC/git-trees" ] || { echo "install.sh: git-trees not found in $SRC" >&2; exit 1; }

mkdir -p "$DEST" || exit 1
install -m 0755 "$SRC/git-trees" "$DEST/git-trees" || exit 1
echo "installed $DEST/git-trees"

# AGENTS.md template — the curl install does not get this.
if [ -f "$SRC/AGENTS.md.template" ] && [ ! -f "$CFG/AGENTS.md" ]; then
  mkdir -p "$CFG"
  cp "$SRC/AGENTS.md.template" "$CFG/AGENTS.md"
  echo "installed $CFG/AGENTS.md (template; used by init or root --agents to seed the container root)"
fi

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "warning: $DEST is not on PATH — add it to use \`git trees\`" >&2 ;;
esac

echo
echo "try: git trees help"

if [ -z "${TREES_ORG:-}" ]; then
  echo
  echo "optional: set a default org so you can write 'git trees init <repo>'"
  echo "  echo 'export TREES_ORG=your-org' >> ~/.zshrc && source ~/.zshrc"
fi
