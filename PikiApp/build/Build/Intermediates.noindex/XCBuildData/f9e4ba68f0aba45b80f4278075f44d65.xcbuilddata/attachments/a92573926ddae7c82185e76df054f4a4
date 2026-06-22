#!/bin/sh
set -euo pipefail
RUNTIME_BUILD_ROOT="${SRCROOT}/.build/runtime-bundle"
APP_RESOURCES="${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
python3 "${SRCROOT}/../scripts/build_runtime_bundle.py"
mkdir -p "$APP_RESOURCES"
rm -rf "$APP_RESOURCES/PikiRuntime"
cp -R "${RUNTIME_BUILD_ROOT}/Contents/Resources/PikiRuntime" "$APP_RESOURCES/"
cp -f "${RUNTIME_BUILD_ROOT}/Contents/Resources/runtime-paths.json" "$APP_RESOURCES/"

