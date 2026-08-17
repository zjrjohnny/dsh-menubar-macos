#!/bin/bash
# 验证 launchctl 语义，仅使用专用 throwaway label，并在任何退出路径清理 job 与文件。
set -euo pipefail

if [ "$(uname -s)" != Darwin ]; then
  echo "SKIP: 仅支持 macOS"
  exit 0
fi

UID_VALUE="$(id -u)"
DOMAIN="gui/$UID_VALUE"
# launchctl 没有删除单项 override 的接口，因此使用稳定 label，避免每次测试
# 都在 print-disabled 中留下一个新的 enabled 记录。
LABEL="com.zjr.dshmenu-test.disabled-matrix.$UID_VALUE"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dshmenu-launchctl.XXXXXX")"
PLIST="$TMP_ROOT/$LABEL.plist"

cleanup() {
  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  launchctl enable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM HUP

launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl enable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true

sed \
  -e "s|__LABEL__|$LABEL|g" \
  -e "s|__OUT__|$TMP_ROOT/out.log|g" \
  > "$PLIST" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>__LABEL__</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>echo started; exec /bin/sleep 30</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>__OUT__</string>
</dict>
</plist>
PLIST_EOF

/usr/bin/plutil -lint "$PLIST" >/dev/null

assert_disabled() {
  local output
  output="$(launchctl print-disabled "$DOMAIN")"
  printf '%s\n' "$output" | grep -E -q \
    "[\"']?$LABEL[\"']?[[:space:]]*=>[[:space:]]*(true|disabled)" || {
      echo "FAIL: $LABEL 未显示为 disabled" >&2
      return 1
    }
}

echo "  [1/5] enabled + unloaded 可以 bootstrap"
launchctl enable "$DOMAIN/$LABEL"
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl print "$DOMAIN/$LABEL" >/dev/null

echo "  [2/5] disable 不卸载已加载 job"
launchctl disable "$DOMAIN/$LABEL"
assert_disabled
launchctl print "$DOMAIN/$LABEL" >/dev/null

echo "  [3/5] disabled + loaded 可以 kickstart"
launchctl kill SIGTERM "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl kickstart -k "$DOMAIN/$LABEL"
launchctl print "$DOMAIN/$LABEL" >/dev/null

echo "  [4/5] disabled + unloaded 的 bootstrap 必须失败"
launchctl bootout "$DOMAIN/$LABEL"
if launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1; then
  echo "FAIL: disabled + unloaded bootstrap 意外成功" >&2
  exit 1
fi

echo "  [5/5] 临时 enable -> bootstrap -> disable -> kickstart 保留偏好"
launchctl enable "$DOMAIN/$LABEL"
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl disable "$DOMAIN/$LABEL"
launchctl kickstart -k "$DOMAIN/$LABEL"
assert_disabled
launchctl print "$DOMAIN/$LABEL" >/dev/null

echo "PASS: throwaway LaunchAgent 矩阵符合预期"
