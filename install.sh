#!/usr/bin/env bash
# install.sh — install git-trees onto PATH
#
#   ./install.sh                      install to ~/.local/bin
#   ./install.sh /usr/local/bin       install elsewhere
#
# Also works with no repo around it, piped straight from the raw URL:
#
#   curl -fsSL .../install.sh | bash
#   TREES_DEST=/usr/local/bin curl -fsSL .../install.sh | bash
#
# A piped script gets no positional arguments, so TREES_DEST is the only way to
# choose a destination on that path.

set -uo pipefail

# Pinned to main: main is the stable release for this project.
BASE_URL="${TREES_BASE_URL:-https://raw.githubusercontent.com/brightdigit/git-trees/main}"

SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SRC=""
CFG="$HOME/.config/git-trees"

# Positional wins for the clone path; TREES_DEST is the piped path's only lever.
DEST="${1:-${TREES_DEST:-$HOME/.local/bin}}"

# Fetch one file to a path. Verifies the transfer rather than trusting that a
# file appeared: a truncated or 404 body installed onto PATH is the worst
# outcome here, and `curl -o` leaves an empty file behind on failure.
fetch() { # fetch <url> <out>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1" || return 1
  else
    echo "install.sh: need curl or wget to download $1" >&2
    return 1
  fi
  [ -s "$2" ]
}

# No repo around the script — piped into bash, or copied off somewhere alone.
if [ -z "$SRC" ] || [ ! -f "$SRC/git-trees" ]; then
  SRC=$(mktemp -d "${TMPDIR:-/tmp}/git-trees-install.XXXXXX") || exit 1
  trap 'rm -rf "$SRC"' EXIT

  echo "downloading git-trees from $BASE_URL" >&2
  fetch "$BASE_URL/git-trees" "$SRC/git-trees" || {
    echo "install.sh: failed to download git-trees" >&2; exit 1; }
  # The template is optional at install time; git-trees warns without it.
  fetch "$BASE_URL/AGENTS.md.template" "$SRC/AGENTS.md.template" || {
    echo "warning: failed to download AGENTS.md.template — skipping" >&2
    rm -f "$SRC/AGENTS.md.template"
  }
fi

mkdir -p "$DEST" || exit 1
install -m 0755 "$SRC/git-trees" "$DEST/git-trees" || exit 1
echo "installed $DEST/git-trees"

# AGENTS.md template — the curl path installs this too.
if [ -f "$SRC/AGENTS.md.template" ] && [ ! -e "$CFG/AGENTS.md" ] && [ ! -L "$CFG/AGENTS.md" ]; then
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
