#!/bin/bash
# uninstall.sh — 卸载 DSh 后台服务 + 菜单栏控制器，保留用户数据与端口配置
set -euo pipefail
cd "$(dirname "$0")"

UID_VALUE="$(id -u)"
DOMAIN="gui/$UID_VALUE"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
MANAGED_BIN="$DSH_HOME/dshmenu/bin"
MANAGED_MARKER="$DSH_HOME/dshmenu/.managed-by-dshmenu"

bootout_if_loaded() {
  local label="$1"
  local job="$DOMAIN/$label"
  if launchctl print "$job" >/dev/null 2>&1; then
    if ! launchctl bootout "$job"; then
      echo "错误: 无法卸载 $job" >&2
      return 1
    fi
  fi
}

normalize_enabled_override() {
  local label="$1"
  local job="$DOMAIN/$label"
  if ! launchctl enable "$job"; then
    echo "错误: 无法把 $job 的 launchd override 归一为 enabled" >&2
    return 1
  fi
}

echo "==> 卸载 LaunchAgent"
for label in com.zjr.dsh-menubar com.zjr.dsh-web com.zjr.dsh-logrotate; do
  bootout_if_loaded "$label"
  # launchctl 没有删除单项 override 的接口；显式归一为 enabled，避免历史 disabled 状态阻塞 fresh install。
  normalize_enabled_override "$label"
  rm -f "$LAUNCH_AGENTS/$label.plist"
done

echo "==> 结束残留菜单栏进程"
pkill -x DShMenu 2>/dev/null || true

echo "==> 删除应用与项目自有运行文件"
rm -rf "$HOME/Applications/DShMenu.app"
if [ -f "$MANAGED_MARKER" ]; then
  for file in node dsh npm npx pnpm corepack rotate_logs.sh; do
    rm -f "$MANAGED_BIN/$file"
  done
  rmdir "$MANAGED_BIN" 2>/dev/null || true
  rm -f "$MANAGED_MARKER"
  rmdir "$DSH_HOME/dshmenu" 2>/dev/null || true
elif [ -d "$DSH_HOME/dshmenu" ]; then
  echo "警告: $DSH_HOME/dshmenu 缺少所有权标记，已保留以避免误删用户文件" >&2
fi

echo "==> 清理服务日志（保留会话、存储和端口配置）"
rm -f "$DSH_HOME/logs/dsh-web.out.log" "$DSH_HOME/logs/dsh-web.err.log"
rm -f "$DSH_HOME/logs/dsh-web.out.log".* "$DSH_HOME/logs/dsh-web.err.log".* 2>/dev/null || true

echo ""
echo "已卸载。以下用户数据已保留:"
echo "  - $DSH_HOME/DShMenu.config.plist（端口配置）"
echo "  - $DSH_HOME/sessions、storages 等 DSh 数据"
echo "  - 旧版本可能创建的 $DSH_HOME/bin（为避免误删用户文件，不自动处理）"
echo "launchd overrides 已显式归一为 enabled，确保将来重新安装按 fresh install 默认启用。"
echo "如还想移除全局 dsh CLI，可执行: npm uninstall -g @deepseek-ai/dsh"
