#!/bin/bash
# build_app.sh — 编译 Swift 源码并打包 DShMenu.app
set -euo pipefail
cd "$(dirname "$0")"

OUTPUT_APP="${DSHMENU_BUILD_OUTPUT:-build/DShMenu.app}"
REQUIRE_OUTPUT_VERIFY="${DSHMENU_REQUIRE_OUTPUT_VERIFY:-0}"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dshmenu-build.XXXXXX")"
APP="$BUILD_ROOT/DShMenu.app"
cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 DShMenu (swiftc)"
swiftc -O DShMenu/main.swift -o "$APP/Contents/MacOS/DShMenu"
echo "==> Info.plist"
cp DShMenu/Info.plist "$APP/Contents/Info.plist"

echo "==> 生成应用图标"
if [ -f DShMenu/AppIcon.icns ]; then
  cp DShMenu/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
  echo "   已使用打包图标"
elif swiftc -O make_icon.swift -o "$BUILD_ROOT/make_icon" 2>/dev/null && \
    "$BUILD_ROOT/make_icon" "$BUILD_ROOT/icon.png" >/dev/null 2>&1; then
  mkdir -p "$BUILD_ROOT/icon.iconset"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$BUILD_ROOT/icon.png" \
      --out "$BUILD_ROOT/icon.iconset/icon_${s}x${s}.png" >/dev/null 2>&1 || true
    doubled=$((s * 2))
    sips -z "$doubled" "$doubled" "$BUILD_ROOT/icon.png" \
      --out "$BUILD_ROOT/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
  done
  if iconutil -c icns "$BUILD_ROOT/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
    echo "   图标已生成"
  else
    echo "   图标打包失败（跳过，不影响功能）"
  fi
else
  echo "   图标生成失败（跳过，不影响功能）"
fi

echo "==> Ad-hoc 签名"
# iCloud/File Provider 目录可能给新建 bundle 附加 FinderInfo 等扩展属性；
# codesign 会拒绝签署带这些元数据的 bundle，因此签名前统一清理。
/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> 发布构建产物"
rm -rf "$OUTPUT_APP"
mkdir -p "$(dirname "$OUTPUT_APP")"
/usr/bin/ditto --norsrc "$APP" "$OUTPUT_APP"
# File Provider 可能给复制后的 bundle 根重新附加 FinderInfo；清理这些元数据
# 不会修改已签名的 bundle 内容，但能避免后续 strict verify 拒绝它。
/usr/bin/xattr -cr "$OUTPUT_APP"
if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"; then
  if [ "$REQUIRE_OUTPUT_VERIFY" -eq 1 ]; then
    echo "错误: 发布位置的 App 签名验证失败" >&2
    exit 1
  fi
  echo "警告: 发布位置被 File Provider 重新附加元数据；临时构建的签名已验证，安装器会在隔离目录再次验证" >&2
fi

case "$OUTPUT_APP" in
  /*) OUTPUT_DISPLAY="$OUTPUT_APP" ;;
  *) OUTPUT_DISPLAY="$(pwd)/$OUTPUT_APP" ;;
esac
echo "==> 完成: $OUTPUT_DISPLAY"
