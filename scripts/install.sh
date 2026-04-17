#!/usr/bin/env bash
# pimbt local installer.
#
# Builds the JS target with MoonBit, then installs a wrapper script to
# $PREFIX/bin/pimbt (default: $HOME/.local/bin). The wrapper invokes node
# on the bundled main.js.
#
# Usage:
#   ./scripts/install.sh                 # install to ~/.local/bin
#   PREFIX=/usr/local ./scripts/install.sh   # install to /usr/local/bin (needs sudo)
#   ./scripts/install.sh --symlink       # symlink main.js (for dev; re-build updates live)
#   ./scripts/install.sh --uninstall     # remove the installed pimbt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/pimbt"
BIN_PATH="$BIN_DIR/pimbt"
SYMLINK_MODE=false
UNINSTALL_MODE=false

for arg in "$@"; do
  case "$arg" in
    --symlink) SYMLINK_MODE=true ;;
    --uninstall) UNINSTALL_MODE=true ;;
    -h|--help)
      cat <<EOF
pimbt installer

Usage:
  $0                   # install to ~/.local/bin (copies main.js)
  PREFIX=/usr/local $0 # install to /usr/local/bin
  $0 --symlink         # symlink instead of copying (dev mode)
  $0 --uninstall       # remove installed pimbt

Requirements:
  - MoonBit toolchain (https://www.moonbitlang.com/download/)
  - Node.js 18+
EOF
      exit 0
      ;;
  esac
done

# --- Uninstall ---
if $UNINSTALL_MODE; then
  rm -f "$BIN_PATH"
  rm -rf "$LIB_DIR"
  echo "Removed $BIN_PATH and $LIB_DIR"
  exit 0
fi

# --- Checks ---
if ! command -v moon >/dev/null 2>&1; then
  echo "Error: moon not found in PATH. Install MoonBit: https://www.moonbitlang.com/download/" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "Error: node not found in PATH. Install Node.js 18+." >&2
  exit 1
fi

NODE_MAJOR=$(node -e 'process.stdout.write(String(process.versions.node.split(".")[0]))')
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "Error: Node.js 18+ required (found: $(node --version))" >&2
  exit 1
fi

# --- Build ---
echo "Building pimbt (release, JS target)..."
cd "$REPO_ROOT"
moon build --target js --release

BUILD_JS="$REPO_ROOT/_build/js/release/build/src/main/main.js"
if [ ! -f "$BUILD_JS" ]; then
  echo "Error: build output not found: $BUILD_JS" >&2
  exit 1
fi

# --- Install ---
mkdir -p "$BIN_DIR" "$LIB_DIR"

if $SYMLINK_MODE; then
  ln -sf "$BUILD_JS" "$LIB_DIR/main.js"
  echo "Symlinked $LIB_DIR/main.js -> $BUILD_JS"
else
  cp "$BUILD_JS" "$LIB_DIR/main.js"
  echo "Copied build to $LIB_DIR/main.js"
fi

# Write wrapper
cat > "$BIN_PATH" <<WRAPPER
#!/usr/bin/env bash
# pimbt wrapper — invokes the bundled MoonBit/JS entry.
exec node "$LIB_DIR/main.js" "\$@"
WRAPPER
chmod +x "$BIN_PATH"

echo
echo "✓ Installed pimbt to $BIN_PATH"
echo

# --- PATH hint ---
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo "Note: $BIN_DIR is not in your PATH."
    echo "Add this to your shell rc (e.g. ~/.zshrc or ~/.bashrc):"
    echo
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    echo
    ;;
esac

echo "Next steps:"
echo "  pimbt --help"
echo "  pimbt login                  # authenticate with NyxID"
echo "  pimbt providers connect openai"
echo "  pimbt --api nyxid-gateway --model gpt-5.4 \"hello\""
