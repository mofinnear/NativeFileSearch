#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_ROOT="$PROJECT_ROOT/dist"
APP_PATH="$DIST_ROOT/NativeFileSearch.app"
ZIP_PATH="$DIST_ROOT/NativeFileSearch-macOS.zip"
ICON_PATH="$SCRIPT_DIR/Assets/NativeFileSearch.icns"
ICONSET_PATH="$SCRIPT_DIR/Assets/NativeFileSearch.iconset"
PRODUCT_PATH="$PROJECT_ROOT/.build/arm64-apple-macosx/release/NativeFileSearch"
LOCAL_SWIFT_WRAPPER="/tmp/nativefilesearch-swiftc-wrapper"
LOCAL_TMP_DIR="/tmp/nativefilesearch-tmp"

mkdir -p "$DIST_ROOT"

if [[ -x "$LOCAL_SWIFT_WRAPPER" ]]; then
    SWIFT_EXEC="$LOCAL_SWIFT_WRAPPER" TMPDIR="$LOCAL_TMP_DIR" \
        swift build --disable-sandbox -c release -j 1 --package-path "$PROJECT_ROOT"
else
    swift build -c release -j 1 --package-path "$PROJECT_ROOT"
fi

if [[ ! -x "$PRODUCT_PATH" ]]; then
    print -u2 "Release executable was not produced: $PRODUCT_PATH"
    exit 1
fi

if [[ ! -f "$ICON_PATH" ]]; then
    print -u2 "Application icon was not found: $ICON_PATH"
    exit 1
fi

rm -rf "$APP_PATH" "$ZIP_PATH"
find "$DIST_ROOT" -type f -name '._*' -delete
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
COPYFILE_DISABLE=1 cp "$PRODUCT_PATH" "$APP_PATH/Contents/MacOS/NativeFileSearch"
COPYFILE_DISABLE=1 cp "$SCRIPT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
if [[ -d "$ICONSET_PATH" ]]; then
    python3 "$SCRIPT_DIR/build-icns.py" "$ICONSET_PATH" "$ICON_PATH"
fi
COPYFILE_DISABLE=1 cp "$ICON_PATH" "$APP_PATH/Contents/Resources/NativeFileSearch.icns"
chmod 755 "$APP_PATH/Contents/MacOS/NativeFileSearch"
find "$APP_PATH" -type f -name '._*' -delete

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_PATH"
fi

find "$APP_PATH" -type f -name '._*' -delete
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"
find "$DIST_ROOT" -type f -name '._*' -delete
print "Built: $APP_PATH"
print "Archive: $ZIP_PATH"
