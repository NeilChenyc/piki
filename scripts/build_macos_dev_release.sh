#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$ROOT_DIR/PikiApp"
PROJECT_YML="$APP_DIR/project.yml"
XCODEPROJ="$APP_DIR/PikiApp.xcodeproj"
DERIVED_DATA="$APP_DIR/.build/dev-release-derived-data"
DIST_ROOT="$ROOT_DIR/dist"
DOC_SOURCE="$ROOT_DIR/docs/development/developer-local-distribution.md"

if [[ "$(/usr/bin/uname -m)" != "arm64" ]]; then
  echo "This developer release script currently supports Apple Silicon builders only." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to regenerate PikiApp.xcodeproj from $PROJECT_YML." >&2
  exit 1
fi

if [[ ! -f "$PROJECT_YML" ]]; then
  echo "Missing project definition: $PROJECT_YML" >&2
  exit 1
fi

echo "Generating Xcode project..."
(
  cd "$APP_DIR"
  xcodegen generate --spec project.yml
)

rm -rf "$DERIVED_DATA"

echo "Building Release app bundle..."
xcodebuild \
  -project "$XCODEPROJ" \
  -scheme PikiApp \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_SOURCE="$DERIVED_DATA/Build/Products/Release/Piki.app"
if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Build succeeded but app bundle was not found at $APP_SOURCE" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SOURCE/Contents/Info.plist")"
RELEASE_DIR="$DIST_ROOT/Piki-${VERSION}-macos-arm64"
ZIP_PATH="$RELEASE_DIR/Piki.app.zip"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "Collecting release artifacts..."
ditto "$APP_SOURCE" "$RELEASE_DIR/Piki.app"
cp "$DOC_SOURCE" "$RELEASE_DIR/INSTALL.md"
cp "$ROOT_DIR/scripts/install_piki_dev_release.sh" "$RELEASE_DIR/install_piki_dev_release.sh"
chmod +x "$RELEASE_DIR/install_piki_dev_release.sh"

ditto -c -k --sequesterRsrc --keepParent "$RELEASE_DIR/Piki.app" "$ZIP_PATH"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "Piki.app.zip" > "SHA256SUMS"
)

echo
echo "Developer release ready:"
echo "  App bundle: $RELEASE_DIR/Piki.app"
echo "  ZIP:        $ZIP_PATH"
echo "  Checksums:  $RELEASE_DIR/SHA256SUMS"
