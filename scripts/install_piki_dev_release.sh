#!/bin/bash
set -euo pipefail

REPO_SLUG="${PIKI_GITHUB_REPO:-NeilChenyc/piki}"
VERSION=""
DEST=""
NO_LAUNCH=0

usage() {
  cat <<'EOF'
Usage: install_piki_dev_release.sh [--version <tag>] [--dest <path>] [--no-launch]

Options:
  --version <tag>   Install a specific GitHub Release tag. Defaults to latest.
  --dest <path>     Install destination directory or final .app path.
  --no-launch       Do not auto-open the app after installation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --dest)
      DEST="${2:-}"
      shift 2
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

resolve_destination() {
  if [[ -n "$DEST" ]]; then
    if [[ "$DEST" == *.app ]]; then
      printf "%s\n" "$DEST"
    else
      printf "%s\n" "$DEST/Piki.app"
    fi
    return
  fi

  if [[ -w "/Applications" ]]; then
    printf "%s\n" "/Applications/Piki.app"
    return
  fi

  mkdir -p "$HOME/Applications"
  printf "%s\n" "$HOME/Applications/Piki.app"
}

if [[ -n "$VERSION" ]]; then
  ZIP_URL="https://github.com/$REPO_SLUG/releases/download/$VERSION/Piki.app.zip"
  SHA_URL="https://github.com/$REPO_SLUG/releases/download/$VERSION/SHA256SUMS"
else
  ZIP_URL="https://github.com/$REPO_SLUG/releases/latest/download/Piki.app.zip"
  SHA_URL="https://github.com/$REPO_SLUG/releases/latest/download/SHA256SUMS"
fi

APP_TARGET="$(resolve_destination)"
APP_PARENT="$(dirname "$APP_TARGET")"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/piki-install.XXXXXX")"
ZIP_PATH="$TMP_DIR/Piki.app.zip"
SHA_PATH="$TMP_DIR/SHA256SUMS"
EXTRACT_DIR="$TMP_DIR/unpacked"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading $ZIP_URL"
curl -L --fail -o "$ZIP_PATH" "$ZIP_URL"

if curl -L --fail -o "$SHA_PATH" "$SHA_URL" >/dev/null 2>&1; then
  EXPECTED_SHA="$(awk '/ Piki\.app\.zip$/{print $1}' "$SHA_PATH")"
  ACTUAL_SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
  if [[ -n "$EXPECTED_SHA" && "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
    echo "Checksum verification failed." >&2
    echo "Expected: $EXPECTED_SHA" >&2
    echo "Actual:   $ACTUAL_SHA" >&2
    exit 1
  fi
fi

mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

SOURCE_APP="$EXTRACT_DIR/Piki.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Archive did not contain Piki.app" >&2
  exit 1
fi

mkdir -p "$APP_PARENT"
rm -rf "$APP_TARGET"
ditto "$SOURCE_APP" "$APP_TARGET"
xattr -dr com.apple.quarantine "$APP_TARGET" 2>/dev/null || true

echo "Installed to $APP_TARGET"
echo "If macOS still blocks first launch, try:"
echo "  xattr -dr com.apple.quarantine \"$APP_TARGET\""
echo "Or right-click the app once and choose Open."

if [[ "$NO_LAUNCH" -eq 0 ]]; then
  open "$APP_TARGET"
fi
