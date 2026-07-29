#!/bin/sh
# Installs the GoodSender CLI binary for the current platform from the latest
# good-sender/mcp release (fat binaries.zip).
set -eu

REPO="good-sender/mcp"
BIN="goodsender"
INSTALL_DIR="${GOODSENDER_INSTALL_DIR:-$HOME/.local/bin}"
MARKER_BEGIN="# >>> GoodSender CLI >>>"
MARKER_END="# <<< GoodSender CLI <<<"

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

shell_name() { basename "${SHELL:-}"; }

profile_path() {
  case "$(shell_name)" in
    zsh) echo "$HOME/.zshrc" ;;
    bash)
      if [ "$(os)" = darwin ]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
    fish) echo "$HOME/.config/fish/config.fish" ;;
    *) echo "$HOME/.profile" ;;
  esac
}

# Read existing GOODSENDER_API_KEY from a previous install block, if any.
existing_api_key() {
  profile="$1"
  [ -f "$profile" ] || return 0
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == begin { in_block = 1; next }
    $0 == end { in_block = 0; next }
    in_block && /GOODSENDER_API_KEY/ {
      line = $0
      sub(/^.*GOODSENDER_API_KEY[= ]+"?/, "", line)
      sub(/".*$/, "", line)
      print line
      exit
    }
  ' "$profile"
}

# Replace the marked block in profile, or append it. Never touches other lines.
upsert_block() {
  profile="$1"
  block="$2"
  mkdir -p "$(dirname "$profile")"
  touch "$profile"

  tmp="$(mktemp)"
  if grep -Fqs "$MARKER_BEGIN" "$profile"; then
    in_block=0
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$line" = "$MARKER_BEGIN" ]; then
        printf '%s\n' "$block"
        in_block=1
        continue
      fi
      if [ "$in_block" -eq 1 ]; then
        [ "$line" = "$MARKER_END" ] && in_block=0
        continue
      fi
      printf '%s\n' "$line"
    done <"$profile" >"$tmp"
    mv "$tmp" "$profile"
  else
    # Drop legacy one-shot block from older install.sh (comment + PATH line only).
    if grep -Fqs "# GoodSender CLI" "$profile"; then
      awk '
        $0 == "# GoodSender CLI" { skip = 1; next }
        skip {
          skip = 0
          if ($0 ~ /PATH/ || $0 ~ /fish_add_path/) next
        }
        { print }
      ' "$profile" >"$tmp"
      mv "$tmp" "$profile"
    fi
    printf '\n%s\n' "$block" >>"$profile"
  fi
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

# API key before PATH / profile exports (read from tty so curl|sh works).
profile="$(profile_path)"
api_key=""
if [ -r /dev/tty ]; then
  printf 'Enter your GoodSender API key (press Enter to skip): ' >/dev/tty
  IFS= read -r api_key </dev/tty || true
fi

if [ -z "$api_key" ]; then
  api_key="$(existing_api_key "$profile" || true)"
  if [ -z "$api_key" ]; then
    printf 'Skipped. Set GOODSENDER_API_KEY to a valid API key for the CLI to work properly.\n'
  else
    printf 'Skipped; keeping the API key already configured in %s\n' "$profile"
  fi
fi

if [ "$(shell_name)" = fish ]; then
  path_line="fish_add_path $INSTALL_DIR"
  if [ -n "$api_key" ]; then
    key_line="set -gx GOODSENDER_API_KEY \"$api_key\""
  else
    key_line=""
  fi
else
  path_line="export PATH=\"$INSTALL_DIR:\$PATH\""
  if [ -n "$api_key" ]; then
    key_line="export GOODSENDER_API_KEY=\"$api_key\""
  else
    key_line=""
  fi
fi

if [ -n "$key_line" ]; then
  block=$(printf '%s\n%s\n%s\n%s' "$MARKER_BEGIN" "$path_line" "$key_line" "$MARKER_END")
else
  block=$(printf '%s\n%s\n%s' "$MARKER_BEGIN" "$path_line" "$MARKER_END")
fi

upsert_block "$profile" "$block"
printf 'Updated PATH / API key exports in %s (restart the shell or: source %s)\n' \
  "$profile" "$profile"
