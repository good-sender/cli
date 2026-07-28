#!/bin/sh
# Installs the GoodSender CLI binary for the current platform from the latest
# good-sender/mcp release (fat binaries.zip).
set -eu

REPO="good-sender/mcp"
BIN="goodsender"
INSTALL_DIR="${GOODSENDER_INSTALL_DIR:-$HOME/.local/bin}"

die() { printf '%s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

os() {
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    Linux) echo linux ;;
    *) die "unsupported OS: $(uname -s) (on Windows use install.ps1)" ;;
  esac
}

arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64) echo amd64 ;;
    *) die "unsupported arch: $(uname -m)" ;;
  esac
}

need curl
need unzip
need mktemp
need mkdir
need chmod
need mv

OS="$(os)"
ARCH="$(arch)"
ASSET="${BIN}-${OS}-${ARCH}"
URL="https://github.com/${REPO}/releases/latest/download/binaries.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'Downloading binaries.zip (%s)...\n' "$ASSET"
curl -fsSL "$URL" -o "$TMP/binaries.zip"
unzip -q -j -o "$TMP/binaries.zip" "$ASSET" -d "$TMP"
chmod +x "$TMP/$ASSET"

mkdir -p "$INSTALL_DIR"
mv -f "$TMP/$ASSET" "$INSTALL_DIR/$BIN"

printf 'Installed %s to %s\n' "$BIN" "$INSTALL_DIR/$BIN"

# Ensure INSTALL_DIR is on PATH for future shells.
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    case "$(basename "${SHELL:-}")" in
      zsh) profile="$HOME/.zshrc" ;;
      bash)
        if [ "$(os)" = darwin ]; then
          profile="$HOME/.bash_profile"
        else
          profile="$HOME/.bashrc"
        fi
        ;;
      fish) profile="$HOME/.config/fish/config.fish" ;;
      *) profile="$HOME/.profile" ;;
    esac

    line="export PATH=\"$INSTALL_DIR:\$PATH\""
    if [ "$(basename "${SHELL:-}")" = fish ]; then
      line="fish_add_path $INSTALL_DIR"
    fi

    mkdir -p "$(dirname "$profile")"
    if [ -f "$profile" ] && grep -Fqs "$INSTALL_DIR" "$profile"; then
      :
    else
      printf '\n# GoodSender CLI\n%s\n' "$line" >>"$profile"
      printf 'Added %s to PATH in %s (restart the shell or: source %s)\n' \
        "$INSTALL_DIR" "$profile" "$profile"
    fi
    ;;
esac
