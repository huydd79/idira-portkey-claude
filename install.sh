#!/bin/bash
# install.sh
# ------------------------------------------------------------------
# Setup script for idira-get-jwt.sh:
#   1. Check required tools (curl, jq, nc, openssl); offer to install
#      missing ones via Homebrew (macOS), or dnf/yum/apt-get (Linux).
#   2. Check Claude Code is installed; if not, run Anthropic's
#      official native installer (https://claude.ai/install.sh).
#   3. Symlink idira-get-jwt.sh into ~/.local/bin so it can be run
#      from anywhere as a command.
#
# Usage: ./install.sh
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/idira-get-jwt.sh"

BIN_DIR="$HOME/.local/bin"
LINK_NAME="idira-get-jwt.sh"

# "nc" is provided by a differently-named package depending on the
# installer; everything else keeps its command name as package name.
pkg_name_for() {
  local tool="$1" manager="$2"
  if [ "$tool" = "nc" ]; then
    case "$manager" in
      brew) echo "netcat" ;;
      dnf|yum) echo "nmap-ncat" ;;
      apt-get) echo "netcat-openbsd" ;;
    esac
  else
    echo "$tool"
  fi
}

echo "== Step 1: checking required tools =="
MISSING=()
for tool in curl jq nc openssl; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  [OK] $tool ($(command -v "$tool"))"
  else
    echo "  [MISSING] $tool"
    MISSING+=("$tool")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  MANAGER=""
  for m in brew dnf yum apt-get; do
    command -v "$m" >/dev/null 2>&1 && MANAGER="$m" && break
  done

  if [ -z "$MANAGER" ]; then
    echo "[ERR] Missing tools (${MISSING[*]}) and no supported package manager" >&2
    echo "[ERR] (brew/dnf/yum/apt-get) found. Install them manually, then re-run." >&2
    exit 1
  fi

  PKGS=()
  for tool in "${MISSING[@]}"; do
    PKGS+=("$(pkg_name_for "$tool" "$MANAGER")")
  done

  SUDO=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

  echo "Installing missing tools via $MANAGER: ${PKGS[*]}"
  case "$MANAGER" in
    brew)    brew install "${PKGS[@]}" ;;
    dnf|yum) $SUDO "$MANAGER" install -y "${PKGS[@]}" ;;
    apt-get) $SUDO apt-get update && $SUDO apt-get install -y "${PKGS[@]}" ;;
  esac
fi

echo ""
echo "== Step 2: checking Claude Code =="

if command -v claude >/dev/null 2>&1; then
  echo "  [OK] claude ($(command -v claude)) - $(claude --version 2>&1)"
else
  echo "  [MISSING] claude - installing via official native installer..."
  curl -fsSL https://claude.ai/install.sh | bash
  hash -r 2>/dev/null || true
  if command -v claude >/dev/null 2>&1; then
    echo "  [OK] claude installed ($(command -v claude))"
  else
    echo "  [WARN] claude still not found on PATH after install - open a new terminal and re-run this script." >&2
  fi
fi

echo ""
echo "== Step 3: creating symlink in $BIN_DIR =="

chmod +x "$TARGET_SCRIPT"
mkdir -p "$BIN_DIR"
ln -sf "$TARGET_SCRIPT" "$BIN_DIR/$LINK_NAME"
echo "  [OK] $BIN_DIR/$LINK_NAME -> $TARGET_SCRIPT"

case ":$PATH:" in
  *":$BIN_DIR:"*) echo "  [OK] $BIN_DIR is already in \$PATH" ;;
  *) echo "  [WARN] $BIN_DIR is NOT in \$PATH - add it to your shell profile (~/.zshrc):" >&2
     echo "         export PATH=\"$BIN_DIR:\$PATH\"" >&2 ;;
esac

echo ""
echo "Done. Run: $LINK_NAME"
