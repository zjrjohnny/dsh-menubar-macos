#!/bin/bash
# 隔离的静态与临时目录检查；默认不操作生产 LaunchAgent。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dshmenu-check.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "==> Shell 语法"
for script in build_app.sh install.sh uninstall.sh rotate_logs.sh tests/*.sh; do
  /bin/bash -n "$script"
done
if rg -n -P '\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]' install.sh uninstall.sh build_app.sh tests/*.sh; then
  fail "Shell 变量紧邻非 ASCII 字符；请使用 \${VAR} 明确变量边界"
fi

echo "==> Swift 类型检查"
/usr/bin/swiftc -typecheck \
  -strict-concurrency=complete \
  -warn-concurrency \
  -target arm64-apple-macosx12.0 \
  -module-cache-path "$TMP_ROOT/swift-module-cache" \
  DShMenu/main.swift
/usr/bin/swiftc -typecheck \
  -D DSHMENU_SERVICE_TEST \
  -strict-concurrency=complete \
  -warn-concurrency \
  -target arm64-apple-macosx12.0 \
  -module-cache-path "$TMP_ROOT/swift-module-cache" \
  DShMenu/main.swift

echo "==> plist 模板语法"
for template in com.zjr.dsh-*.plist.template; do
  /usr/bin/plutil -lint "$template" >/dev/null
done
/usr/bin/plutil -lint DShMenu/Info.plist >/dev/null
/usr/bin/plutil -lint DShMenu.config.plist.template >/dev/null

echo "==> 配置与模板契约"
for source in DShMenu/main.swift install.sh README.md; do
  rg -q 'DShMenu\.config\.plist' "$source" \
    || fail "$source 缺少 DShMenu.config.plist 契约"
done
rg -q '<key>Port</key>' DShMenu.config.plist.template \
  || fail "默认配置模板缺少 Port 键"
PORT_TYPE="$(/usr/bin/plutil -type Port DShMenu.config.plist.template 2>/dev/null || true)"
[ "$PORT_TYPE" = integer ] || fail "默认配置模板的 Port 不是整数"
DEFAULT_PORT="$(/usr/bin/plutil -extract Port raw -o - DShMenu.config.plist.template 2>/dev/null || true)"
[ "$DEFAULT_PORT" = 3080 ] || fail "默认端口不是 3080"
rg -q 'read_port' install.sh \
  || fail "install.sh 未验证 Port 配置"
rg -q 'wait_for_job_unloaded' install.sh \
  || fail "install.sh 未等待 bootout 完全生效"
rg -q 'bootstrap_job' install.sh \
  || fail "install.sh 未对 Tahoe 的短暂 bootstrap exit 5 做有界重试"
rg -q 'wait_for_dsh_identity' install.sh \
  || fail "install.sh 未等待 DSh 身份探活"
rg -q '\$3 == "disabled"' install.sh \
  || fail "install.sh 的 disabled 状态解析未识别 Tahoe 的 disabled 文本"
rg -q '\$3 == "true"' install.sh \
  || fail "install.sh 的 disabled 状态解析未兼容旧式 true 文本"
rg -q '__PORT__' com.zjr.dsh-web.plist.template \
  || fail "Web plist 模板缺少 __PORT__ 占位符"
rg -q 'plutil -replace ProgramArguments\.4 -string "\$PORT"' install.sh \
  || fail "install.sh 未通过 plutil 写入端口"
rg -q -- '--port' com.zjr.dsh-web.plist.template \
  || fail "Web Agent 未把配置端口传给 dsh web"
if rg -q '/\.nvm/versions/node|/Cellar/node' com.zjr.dsh-web.plist.template; then
  fail "Web plist 模板仍包含易变的 Node 版本路径"
fi
for variable in USER SHELL LANG TMPDIR; do
  rg -q "<key>${variable}</key>" com.zjr.dsh-web.plist.template \
    || fail "Web plist 缺少环境变量 ${variable}"
done

echo "==> 开源发布契约"
[ -f LICENSE ] || fail "缺少 LICENSE"
rg -q '^MIT License$' LICENSE || fail "LICENSE 不是 MIT 文本"
[ -f README.zh-CN.md ] || fail "缺少中文 README"
[ -f NOTICE.md ] || fail "缺少独立项目与上游声明"
[ -f SECURITY.md ] || fail "缺少安全报告说明"
[ -f CONTRIBUTING.md ] || fail "缺少贡献说明"
[ -f .gitignore ] || fail "缺少 .gitignore"
[ -f .gitattributes ] || fail "缺少 .gitattributes"
rg -q '^build/$' .gitignore || fail ".gitignore 未排除构建目录"
rg -q 'independent community project' README.md NOTICE.md \
  || fail "缺少非官方社区项目声明"
rg -q 'dshmenu/bin' install.sh uninstall.sh README.md README.zh-CN.md \
  || fail "项目管理运行目录未使用专属命名空间"
if rg -q 'run_or_die.*npm install|^[[:space:]]*npm install -g' install.sh; then
  fail "install.sh 不应静默全局安装 dsh"
fi
rg -q 'command -v dsh' install.sh || fail "install.sh 未检查现有 dsh"
rg -q 'plutil -replace' install.sh || fail "install.sh 未使用 plutil 安全渲染 plist"
rg -q 'port_listener_pids' install.sh || fail "install.sh 未在切换前检查端口占用"
rg -q 'func tr\(' DShMenu/main.swift || fail "菜单栏 UI 缺少中英文切换"
[ -f .github/workflows/ci.yml ] || fail "缺少 macOS CI"

echo "==> 构建脚本签名契约"
rg -q 'codesign --force --sign -' build_app.sh \
  || fail "build_app.sh 缺少显式 ad-hoc 签名"
rg -q 'codesign --verify' build_app.sh \
  || fail "build_app.sh 缺少签名验证"

echo "==> 临时 DSH_HOME 日志轮转"
TEST_HOME="$TMP_ROOT/dsh-home"
mkdir -p "$TEST_HOME/logs"
LOG_FILE="$TEST_HOME/logs/dsh-web.err.log"
/bin/dd if=/dev/zero of="$LOG_FILE" bs=1048576 count=11 2>/dev/null
BEFORE_INODE="$(stat -f%i "$LOG_FILE")"
DSH_HOME="$TEST_HOME" /bin/bash rotate_logs.sh
AFTER_INODE="$(stat -f%i "$LOG_FILE")"
[ "$BEFORE_INODE" = "$AFTER_INODE" ] || fail "copytruncate 改变了原日志 inode"
[ "$(stat -f%z "$LOG_FILE")" -eq 0 ] || fail "原日志未被截断"
[ "$(stat -f%z "$LOG_FILE.1")" -eq $((11 * 1024 * 1024)) ] \
  || fail "轮转副本大小错误"

echo "==> 隔离安装失败回滚"
/bin/bash tests/test_install_rollback.sh

if [ "${RUN_LAUNCHCTL_MATRIX:-0}" = 1 ]; then
  echo "==> throwaway LaunchAgent disabled/bootstrap 矩阵"
  /bin/bash tests/test_launchctl_disabled_matrix.sh
else
  echo "==> 跳过 launchctl 状态矩阵（设置 RUN_LAUNCHCTL_MATRIX=1 可运行）"
fi

echo "PASS: 所有已启用检查通过"
