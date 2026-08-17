#!/bin/bash
# rotate_logs.sh — copytruncate 轮转 dsh 日志（与 launchd 保持打开的文件句柄兼容）。
# 超过 MAX_BYTES 即截断，最多保留 KEEP 份历史副本（*.log.1 .. *.log.KEEP）。
set -euo pipefail

LOG_DIR="${DSH_HOME:-$HOME/.dsh}/logs"
MAX_BYTES=$((10 * 1024 * 1024))   # 10 MB
KEEP=5

mkdir -p "$LOG_DIR"

for f in "$LOG_DIR"/*.log; do
  [ -f "$f" ] || continue
  size=$(stat -f%z "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt "$MAX_BYTES" ]; then
    # 旧副本整体后移一位（f.4 -> f.5, ..., f.1 -> f.2）
    i=$KEEP
    while [ "$i" -ge 1 ]; do
      prev=$((i - 1))
      if [ -f "$f.$prev" ]; then
        mv -f "$f.$prev" "$f.$i"
      fi
      i=$prev
    done
    cp "$f" "$f.1"
    : > "$f"   # 原地截断，保持 inode 不变，launchd 继续写同一个文件
  fi
done
