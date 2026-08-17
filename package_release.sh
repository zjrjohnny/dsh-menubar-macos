#!/bin/bash
# Build the source-based macOS installer archive used by GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - DShMenu/Info.plist)}"
case "$VERSION" in
  ''|*[!0-9A-Za-z.-]*)
    echo "error: invalid version: $VERSION" >&2
    exit 2
    ;;
esac

DIST_DIR="${DSHMENU_DIST_DIR:-$ROOT/dist}"
PACKAGE_NAME="DShMenu-v${VERSION}-macos-source-installer"
ARCHIVE="$DIST_DIR/$PACKAGE_NAME.zip"
CHECKSUM="$DIST_DIR/$PACKAGE_NAME.sha256"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dshmenu-package.XXXXXX")"
PACKAGE_DIR="$STAGE_ROOT/$PACKAGE_NAME"

cleanup() {
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

mkdir -p "$PACKAGE_DIR" "$DIST_DIR"

release_files=(
  DShMenu
  DShMenu.config.plist.template
  Install.command
  Uninstall.command
  build_app.sh
  install.sh
  uninstall.sh
  rotate_logs.sh
  make_icon.swift
  com.zjr.dsh-web.plist.template
  com.zjr.dsh-menubar.plist.template
  com.zjr.dsh-logrotate.plist.template
  INSTALL.md
  INSTALL.zh-CN.md
  README.md
  README.zh-CN.md
  CHANGELOG.md
  SECURITY.md
  LICENSE
  NOTICE.md
)

for source in "${release_files[@]}"; do
  [ -e "$source" ] || {
    echo "error: release input is missing: $source" >&2
    exit 1
  }
  /bin/cp -R "$source" "$PACKAGE_DIR/$source"
done

chmod +x \
  "$PACKAGE_DIR/Install.command" \
  "$PACKAGE_DIR/Uninstall.command" \
  "$PACKAGE_DIR/build_app.sh" \
  "$PACKAGE_DIR/install.sh" \
  "$PACKAGE_DIR/uninstall.sh" \
  "$PACKAGE_DIR/rotate_logs.sh"

if find "$PACKAGE_DIR" -name '.DS_Store' -o -name '*.log' | grep -q .; then
  echo "error: private/runtime files entered the release staging directory" >&2
  exit 1
fi

rm -f "$ARCHIVE" "$CHECKSUM"
/usr/bin/ditto -c -k --keepParent --norsrc "$PACKAGE_DIR" "$ARCHIVE"
/usr/bin/unzip -tq "$ARCHIVE" >/dev/null

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

echo "Release package: $ARCHIVE"
echo "SHA-256 file:   $CHECKSUM"
