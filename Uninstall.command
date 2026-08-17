#!/bin/bash
# Finder/Terminal-friendly wrapper for the conservative uninstaller.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

if [ "${1:-}" != "--yes" ]; then
  echo "This removes DShMenu, its LaunchAgents, managed links, and service logs."
  echo "Sessions, storages, the port configuration, and global dsh are preserved."
  echo "这会删除 DShMenu、LaunchAgent、项目管理链接和服务日志。"
  echo "会话、存储、端口配置和全局 dsh 将被保留。"
  printf 'Continue? / 是否继续？ [y/N] '
  IFS= read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Cancelled. / 已取消。"; exit 0 ;;
  esac
fi

/bin/bash ./uninstall.sh
status=$?

echo
if [ "$status" -eq 0 ]; then
  echo "Uninstall completed. / 卸载完成。"
else
  echo "Uninstall failed with exit code $status. / 卸载失败，退出码 $status。"
fi
if [ -t 0 ] && [ "${DSHMENU_NO_PAUSE:-0}" != 1 ]; then
  printf 'Press Return to close / 按回车键关闭... '
  IFS= read -r _
fi
exit "$status"
