#!/bin/bash
# Finder/Terminal-friendly wrapper for the source installer.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

if [ "${1:-}" != "-h" ] && [ "${1:-}" != "--help" ] && [ -z "${DSH_WORKDIR:-}" ]; then
  DEFAULT_WORKDIR="$HOME/Documents"
  [ -d "$DEFAULT_WORKDIR" ] || DEFAULT_WORKDIR="$HOME"
  if [ -t 0 ] && [ "${DSHMENU_NONINTERACTIVE:-0}" != 1 ]; then
    echo "DShMenu source installer / 源码安装器"
    echo "The Web workspace is the directory dsh will be allowed to browse."
    echo "Web 工作目录是 dsh Web UI 可以浏览的目录。"
    printf 'Workspace / 工作目录 [%s]: ' "$DEFAULT_WORKDIR"
    IFS= read -r selected_workdir
    DSH_WORKDIR="${selected_workdir:-$DEFAULT_WORKDIR}"
  else
    DSH_WORKDIR="$DEFAULT_WORKDIR"
  fi
  export DSH_WORKDIR
fi

/bin/bash ./install.sh "$@"
status=$?

echo
if [ "$status" -eq 0 ]; then
  echo "DShMenu completed successfully. / DShMenu 已成功完成。"
else
  echo "DShMenu failed with exit code $status. Review the messages above."
  echo "DShMenu 执行失败（退出码 $status），请查看上方信息。"
fi

if [ -t 0 ] && [ "${DSHMENU_NO_PAUSE:-0}" != 1 ]; then
  printf 'Press Return to close / 按回车键关闭... '
  IFS= read -r _
fi
exit "$status"
