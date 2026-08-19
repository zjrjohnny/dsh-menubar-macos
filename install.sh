#!/bin/bash
# install.sh — 一键安装 DSh 后台服务 + 菜单栏控制器
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CHECK_ONLY=0
case "${1:-}" in
  "") ;;
  --check) CHECK_ONLY=1 ;;
  -h|--help)
    cat <<'EOF'
Usage: ./install.sh [--check]

  --check  Build and validate all artifacts without changing installed files
           or LaunchAgents.

Environment:
  DSH_HOME     DeepSeek Harness data directory (default: ~/.dsh)
  DSH_WORKDIR  Initial Web workspace root (default: repository parent)
EOF
    exit 0
    ;;
  *)
    echo "错误: 未知参数: $1" >&2
    exit 2
    ;;
esac

WEB_LABEL="com.zjr.dsh-web"
MENUBAR_LABEL="com.zjr.dsh-menubar"
LOGROTATE_LABEL="com.zjr.dsh-logrotate"
UID_VALUE="$(id -u)"
DOMAIN="gui/$UID_VALUE"
WEB_JOB="$DOMAIN/$WEB_LABEL"
MENUBAR_JOB="$DOMAIN/$MENUBAR_LABEL"
LOGROTATE_JOB="$DOMAIN/$LOGROTATE_LABEL"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
WEB_PLIST="$LAUNCH_AGENTS/$WEB_LABEL.plist"
MENUBAR_PLIST="$LAUNCH_AGENTS/$MENUBAR_LABEL.plist"
LOGROTATE_PLIST="$LAUNCH_AGENTS/$LOGROTATE_LABEL.plist"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
case "$DSH_HOME" in
  /*) ;;
  *)
    echo "错误: DSH_HOME 必须是绝对路径: $DSH_HOME" >&2
    exit 2
    ;;
esac
CONFIG_PLIST="$DSH_HOME/DShMenu.config.plist"
LOG_DIR="$DSH_HOME/logs"
# 只管理专属子目录，避免覆盖用户或上游放在 ~/.dsh/bin 的同名文件。
MANAGED_ROOT="$DSH_HOME/dshmenu"
MANAGED_MARKER="$MANAGED_ROOT/.managed-by-dshmenu"
STABLE_BIN="$MANAGED_ROOT/bin"
APP_DIR="$HOME/Applications/DShMenu.app"
APP_BIN="$APP_DIR/Contents/MacOS/DShMenu"
STAGE_DIR=""
BACKUP_DIR=""
WEB_TEMP_ENABLED=0
WEB_WAS_DISABLED=0
WEB_WAS_LOADED=0
WEB_WAS_RUNNING=0
MENUBAR_WAS_LOADED=0
LOGROTATE_WAS_LOADED=0
MUTATION_STARTED=0
CONFIG_CREATED=0

die() {
  echo "错误: $*" >&2
  exit 1
}

run_or_die() {
  local description="$1"
  shift
  if ! "$@"; then
    die "$description"
  fi
}

cleanup() {
  local exit_code=$?
  trap - EXIT
  if [ "$exit_code" -ne 0 ] && [ "$MUTATION_STARTED" -eq 1 ]; then
    rollback_install || true
  fi
  if [ "$WEB_TEMP_ENABLED" -eq 1 ] && [ "$WEB_WAS_DISABLED" -eq 1 ]; then
    if ! launchctl disable "$WEB_JOB"; then
      echo "警告: 安装退出时无法恢复 Web 服务的 disabled 偏好；请执行: launchctl disable $WEB_JOB" >&2
    fi
  fi
  if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
    rm -rf "$STAGE_DIR"
  fi
  if [ "$exit_code" -ne 0 ]; then
    echo "安装未完成；上方错误包含失败步骤。" >&2
  fi
  exit "$exit_code"
}
trap cleanup EXIT

rollback_install() {
  echo "==> 安装失败，尝试恢复安装前状态" >&2
  set +e

  for rollback_job in "$MENUBAR_JOB" "$WEB_JOB" "$LOGROTATE_JOB"; do
    if job_is_loaded "$rollback_job"; then
      launchctl bootout "$rollback_job" >/dev/null 2>&1 || true
      wait_for_job_unloaded "$rollback_job" 50 >/dev/null 2>&1 || true
    fi
  done

  if [ -d "$BACKUP_DIR/app" ]; then
    rm -rf "$APP_DIR"
    /usr/bin/ditto --norsrc "$BACKUP_DIR/app" "$APP_DIR"
  else
    rm -rf "$APP_DIR"
  fi

  for rollback_label in "$WEB_LABEL" "$MENUBAR_LABEL" "$LOGROTATE_LABEL"; do
    rollback_plist="$LAUNCH_AGENTS/$rollback_label.plist"
    if [ -f "$BACKUP_DIR/$rollback_label.plist" ]; then
      cp "$BACKUP_DIR/$rollback_label.plist" "$rollback_plist"
    else
      rm -f "$rollback_plist"
    fi
  done

  for managed_name in node dsh npm npx pnpm corepack rotate_logs.sh; do
    rm -f "$STABLE_BIN/$managed_name"
    if [ -e "$BACKUP_DIR/managed/$managed_name" ] || [ -L "$BACKUP_DIR/managed/$managed_name" ]; then
      cp -P "$BACKUP_DIR/managed/$managed_name" "$STABLE_BIN/$managed_name"
    fi
  done
  if [ -f "$BACKUP_DIR/managed-marker" ]; then
    touch "$MANAGED_MARKER"
  else
    rm -f "$MANAGED_MARKER"
  fi
  rmdir "$STABLE_BIN" "$MANAGED_ROOT" 2>/dev/null || true
  if [ "$CONFIG_CREATED" -eq 1 ]; then
    rm -f "$CONFIG_PLIST"
  fi

  launchctl enable "$WEB_JOB" >/dev/null 2>&1 || true
  if [ "$WEB_WAS_LOADED" -eq 1 ] && [ -f "$WEB_PLIST" ]; then
    bootstrap_job "$DOMAIN" "$WEB_PLIST" >/dev/null 2>&1 || true
    if [ "$WEB_WAS_RUNNING" -eq 0 ]; then
      launchctl kill SIGTERM "$WEB_JOB" >/dev/null 2>&1 || true
      wait_for_job_not_running "$WEB_JOB" 50 >/dev/null 2>&1 || true
    fi
  fi
  if [ "$WEB_WAS_DISABLED" -eq 1 ]; then
    launchctl disable "$WEB_JOB" >/dev/null 2>&1 || true
  fi
  WEB_TEMP_ENABLED=0

  if [ "$MENUBAR_WAS_LOADED" -eq 1 ] && [ -f "$MENUBAR_PLIST" ]; then
    launchctl enable "$MENUBAR_JOB" >/dev/null 2>&1 || true
    bootstrap_job "$DOMAIN" "$MENUBAR_PLIST" >/dev/null 2>&1 || true
  fi
  if [ "$LOGROTATE_WAS_LOADED" -eq 1 ] && [ -f "$LOGROTATE_PLIST" ]; then
    launchctl enable "$LOGROTATE_JOB" >/dev/null 2>&1 || true
    bootstrap_job "$DOMAIN" "$LOGROTATE_PLIST" >/dev/null 2>&1 || true
  fi

  echo "恢复流程已执行；如服务状态仍异常，请运行 launchctl print 检查三个 job。" >&2
  set -e
  return 0
}

job_is_loaded() {
  launchctl print "$1" >/dev/null 2>&1
}

job_state() {
  launchctl print "$1" 2>/dev/null | awk '/^[[:space:]]*state = / { print $3; exit }'
}

job_pid() {
  launchctl print "$1" 2>/dev/null | awk '/^[[:space:]]*pid = / { print $3; exit }'
}

wait_for_job_state() {
  local job="$1"
  local expected="$2"
  local attempts="${3:-50}"
  local current=""
  local i
  for ((i = 0; i < attempts; i++)); do
    current="$(job_state "$job" || true)"
    if [ "$current" = "$expected" ]; then
      return 0
    fi
    sleep 0.1
  done
  echo "等待 $job 状态变为 $expected 超时（当前: ${current:-unavailable}）" >&2
  return 1
}

wait_for_job_not_running() {
  local job="$1"
  local attempts="${2:-100}"
  local current=""
  local i
  for ((i = 0; i < attempts; i++)); do
    current="$(job_state "$job" || true)"
    if [ "$current" != "running" ]; then
      return 0
    fi
    sleep 0.1
  done
  echo "等待 $job 停止超时（当前仍为 running）" >&2
  return 1
}

wait_for_job_unloaded() {
  local job="$1"
  local attempts="${2:-100}"
  local i
  for ((i = 0; i < attempts; i++)); do
    if ! job_is_loaded "$job"; then
      return 0
    fi
    sleep 0.1
  done
  echo "等待 $job 完全卸载超时" >&2
  return 1
}

bootstrap_job() {
  local domain="$1"
  local plist="$2"
  local attempts="${3:-20}"
  local output=""
  local code=0
  local i
  for ((i = 0; i < attempts; i++)); do
    if output="$(launchctl bootstrap "$domain" "$plist" 2>&1)"; then
      return 0
    else
      code=$?
    fi
    # Tahoe 偶尔在 bootout 已不可查询后仍短暂返回 EX_IOERR(5)。
    # 其他错误无需重试；5 最多等待约 4 秒后把最后诊断交给调用者。
    if [ "$code" -ne 5 ]; then
      break
    fi
    sleep 0.2
  done
  echo "launchctl bootstrap 失败（exit ${code}，plist: ${plist}）" >&2
  [ -z "$output" ] || echo "$output" >&2
  return "$code"
}

wait_for_process_exit() {
  local name="$1"
  local i
  for ((i = 0; i < 50; i++)); do
    if ! pgrep -x "$name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  echo "等待旧进程 $name 退出超时" >&2
  return 1
}

port_listener_pids() {
  local port="$1"
  lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u || true
}

wait_for_dsh_identity() {
  local port="$1"
  local attempts="${2:-100}"
  local response="$STAGE_DIR/health.webmanifest"
  local name=""
  local short_name=""
  local i
  for ((i = 0; i < attempts; i++)); do
    if curl --fail --silent --show-error --max-time 1 \
      "http://127.0.0.1:$port/manifest.webmanifest" -o "$response" 2>/dev/null; then
      name="$(plutil -extract name raw -o - "$response" 2>/dev/null || true)"
      short_name="$(plutil -extract short_name raw -o - "$response" 2>/dev/null || true)"
      if [ "$name" = "DeepSeek Harness" ] || [ "$short_name" = "DSH" ]; then
        return 0
      fi
    fi
    sleep 0.1
  done
  return 1
}

read_port() {
  local config="$1"
  local value
  plutil -lint "$config" >/dev/null || die "端口配置不是有效 plist: $config"
  value="$(plutil -extract Port raw -expect integer -o - "$config" 2>/dev/null)" || \
    die "端口配置缺少整数键 Port: $config"
  [[ "$value" =~ ^[0-9]+$ ]] || die "Port 必须是整数，当前值: $value"
  (( value >= 1 && value <= 65535 )) || die "Port 必须在 1..65535，当前值: $value"
  printf '%s\n' "$value"
}

set_program_arguments() {
  local plist="$1"
  shift
  local index=0
  local argument

  # On macOS Tahoe, replacing a numeric ProgramArguments path inserts a new
  # element instead of replacing that index. Rebuild the array from empty so no
  # template placeholders or duplicate arguments can survive rendering.
  run_or_die "清空 ProgramArguments 失败: $plist" \
    plutil -replace ProgramArguments -json '[]' "$plist"
  for argument in "$@"; do
    run_or_die "写入 ProgramArguments[$index] 失败: $plist" \
      plutil -insert "ProgramArguments.$index" -string "$argument" "$plist"
    index=$((index + 1))
  done
}

assert_program_arguments() {
  local plist="$1"
  shift
  local index=0
  local expected
  local actual

  for expected in "$@"; do
    actual="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$index" "$plist" 2>/dev/null)" || \
      die "ProgramArguments 缺少索引 $index: $plist"
    [ "$actual" = "$expected" ] || \
      die "ProgramArguments[$index] 不匹配: $plist"
    index=$((index + 1))
  done
  if /usr/libexec/PlistBuddy -c "Print :ProgramArguments:$index" "$plist" >/dev/null 2>&1; then
    die "ProgramArguments 包含多余参数（从索引 $index 开始）: $plist"
  fi
}

require_command() {
  local command_name="$1"
  local install_hint="$2"
  command -v "$command_name" >/dev/null 2>&1 || die "找不到 ${command_name}。${install_hint}"
}

echo "=============================================="
echo " DSh 后台服务 + 菜单栏控制器 安装"
echo "=============================================="

# ---------- 1. 环境探测 ----------
require_command swiftc "请先运行 xcode-select --install"
require_command codesign "请先运行 xcode-select --install"
require_command plutil "该工具应由 macOS 提供"
require_command launchctl "该工具应由 macOS 提供"
require_command lsof "该工具应由 macOS 提供"
require_command curl "该工具应由 macOS 提供"
NODE="$(command -v node || true)"
[ -n "$NODE" ] || die "找不到 node，请先安装 Node.js"
WORKDIR="${DSH_WORKDIR:-$(dirname "$SCRIPT_DIR")}"
[ -d "$WORKDIR" ] || die "DSH_WORKDIR 不是已存在的目录: $WORKDIR"
WORKDIR="$(cd "$WORKDIR" && pwd)"
echo "  node      = $NODE"
echo "  DSH_HOME  = $DSH_HOME"
echo "  工作目录  = $WORKDIR (作为 Web UI 的 workspace 根)"

# ---------- 2. 确保 dsh CLI 已由用户安装 ----------
DSH_BIN="$(command -v dsh || true)"
[ -n "$DSH_BIN" ] && [ -x "$DSH_BIN" ] || \
  die "找不到可执行的 dsh。请先运行: npm install -g @deepseek-ai/dsh"
DSH_VERSION="$($DSH_BIN --version 2>/dev/null)" || \
  die "dsh 无法运行；请检查它与当前 Node.js 的版本兼容性"
echo "==> dsh CLI 已存在: $DSH_BIN (版本 ${DSH_VERSION:-unknown})"

NODE_DIR="$(dirname "$NODE")"
USER_NAME="$(id -un)"
SHELL_PATH="${SHELL:-/bin/bash}"
LANG_VALUE="${LANG:-en_US.UTF-8}"
TMPDIR_VALUE="${TMPDIR:-/tmp}"
PATH_VALUE="$STABLE_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# ---------- 3. 在触碰已安装文件/job 之前，完成所有构建与 plist 校验 ----------
STAGE_DIR="$(mktemp -d "${TMPDIR_VALUE%/}/dshmenu-install.XXXXXX")" || die "无法创建安装临时目录"

echo "==> 构建并预检 DShMenu.app"
run_or_die "构建 DShMenu.app 失败" env \
  DSHMENU_BUILD_OUTPUT="$STAGE_DIR/DShMenu.app" \
  DSHMENU_REQUIRE_OUTPUT_VERIFY=1 \
  bash build_app.sh
[ -x "$STAGE_DIR/DShMenu.app/Contents/MacOS/DShMenu" ] || die "构建产物缺少可执行文件"
run_or_die "构建产物 Info.plist 无效" plutil -lint "$STAGE_DIR/DShMenu.app/Contents/Info.plist"

if [ -e "$CONFIG_PLIST" ]; then
  PORT="$(read_port "$CONFIG_PLIST")"
  echo "  保留现有端口配置: $PORT"
else
  run_or_die "暂存默认端口配置失败" cp DShMenu.config.plist.template "$STAGE_DIR/DShMenu.config.plist"
  PORT="$(read_port "$STAGE_DIR/DShMenu.config.plist")"
  echo "  创建默认端口配置: $PORT"
fi

run_or_die "暂存 Web LaunchAgent 模板失败" \
  cp com.zjr.dsh-web.plist.template "$STAGE_DIR/$WEB_LABEL.plist"
set_program_arguments "$STAGE_DIR/$WEB_LABEL.plist" \
  "$STABLE_BIN/node" "$STABLE_BIN/dsh" web --port "$PORT"
assert_program_arguments "$STAGE_DIR/$WEB_LABEL.plist" \
  "$STABLE_BIN/node" "$STABLE_BIN/dsh" web --port "$PORT"
for key_value in \
  "DSH_HOME=$DSH_HOME" \
  "DSH_NODE_PATH=$STABLE_BIN/node" \
  "DSH_CLI_PATH=$STABLE_BIN/dsh" \
  "DSH_PORT=$PORT" \
  "HOME=$HOME" \
  "USER=$USER_NAME" \
  "SHELL=$SHELL_PATH" \
  "LANG=$LANG_VALUE" \
  "TMPDIR=$TMPDIR_VALUE" \
  "PATH=$PATH_VALUE"; do
  key="${key_value%%=*}"
  value="${key_value#*=}"
  run_or_die "写入 Web 环境变量 $key 失败" \
    plutil -replace "EnvironmentVariables.$key" -string "$value" "$STAGE_DIR/$WEB_LABEL.plist"
done
run_or_die "写入 Web 工作目录失败" \
  plutil -replace WorkingDirectory -string "$WORKDIR" "$STAGE_DIR/$WEB_LABEL.plist"
run_or_die "写入 Web 标准输出路径失败" \
  plutil -replace StandardOutPath -string "$LOG_DIR/dsh-web.out.log" "$STAGE_DIR/$WEB_LABEL.plist"
run_or_die "写入 Web 标准错误路径失败" \
  plutil -replace StandardErrorPath -string "$LOG_DIR/dsh-web.err.log" "$STAGE_DIR/$WEB_LABEL.plist"

run_or_die "暂存菜单栏 LaunchAgent 模板失败" \
  cp com.zjr.dsh-menubar.plist.template "$STAGE_DIR/$MENUBAR_LABEL.plist"
set_program_arguments "$STAGE_DIR/$MENUBAR_LABEL.plist" "$APP_BIN"
assert_program_arguments "$STAGE_DIR/$MENUBAR_LABEL.plist" "$APP_BIN"
run_or_die "写入菜单栏 DSH_HOME 失败" \
  plutil -replace EnvironmentVariables.DSH_HOME -string "$DSH_HOME" "$STAGE_DIR/$MENUBAR_LABEL.plist"

run_or_die "暂存日志轮转 LaunchAgent 模板失败" \
  cp com.zjr.dsh-logrotate.plist.template "$STAGE_DIR/$LOGROTATE_LABEL.plist"
set_program_arguments "$STAGE_DIR/$LOGROTATE_LABEL.plist" \
  /bin/bash "$STABLE_BIN/rotate_logs.sh"
assert_program_arguments "$STAGE_DIR/$LOGROTATE_LABEL.plist" \
  /bin/bash "$STABLE_BIN/rotate_logs.sh"
run_or_die "写入日志轮转 DSH_HOME 失败" \
  plutil -replace EnvironmentVariables.DSH_HOME -string "$DSH_HOME" "$STAGE_DIR/$LOGROTATE_LABEL.plist"
run_or_die "写入日志轮转 HOME 失败" \
  plutil -replace EnvironmentVariables.HOME -string "$HOME" "$STAGE_DIR/$LOGROTATE_LABEL.plist"

for plist in "$STAGE_DIR/$WEB_LABEL.plist" "$STAGE_DIR/$MENUBAR_LABEL.plist" "$STAGE_DIR/$LOGROTATE_LABEL.plist"; do
  run_or_die "生成的 LaunchAgent plist 无效: $plist" plutil -lint "$plist"
done
run_or_die "暂存日志轮转脚本失败" cp rotate_logs.sh "$STAGE_DIR/rotate_logs.sh"
run_or_die "日志轮转脚本语法检查失败" bash -n "$STAGE_DIR/rotate_logs.sh"

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "=============================================="
  echo " 预检完成：未修改 App、LaunchAgent 或运行状态"
  echo "  - dsh 版本: ${DSH_VERSION:-unknown}"
  echo "  - 配置端口: $PORT"
  echo "  - 工作目录: $WORKDIR"
  echo "=============================================="
  exit 0
fi

# ---------- 4. 记录 Web 的安装、加载、运行、自启状态 ----------
WEB_WAS_INSTALLED=0
WEB_WAS_LOADED=0
WEB_WAS_RUNNING=0
[ -f "$WEB_PLIST" ] && WEB_WAS_INSTALLED=1
if job_is_loaded "$WEB_JOB"; then
  WEB_WAS_LOADED=1
  [ "$(job_state "$WEB_JOB" || true)" = "running" ] && WEB_WAS_RUNNING=1
fi
DISABLED_OUTPUT="$(launchctl print-disabled "$DOMAIN" 2>&1)" || die "无法读取 launchd disabled 状态: $DISABLED_OUTPUT"
if printf '%s\n' "$DISABLED_OUTPUT" | \
    awk -v label="\"$WEB_LABEL\"" \
      '$1 == label && $2 == "=>" && ($3 == "disabled" || $3 == "true") { found = 1 } END { exit !found }'; then
  WEB_WAS_DISABLED=1
fi
WEB_IS_FRESH=0
if [ "$WEB_WAS_INSTALLED" -eq 0 ] && [ "$WEB_WAS_LOADED" -eq 0 ]; then
  WEB_IS_FRESH=1
fi
echo "  原 Web 状态: installed=$WEB_WAS_INSTALLED loaded=$WEB_WAS_LOADED running=$WEB_WAS_RUNNING disabled=$WEB_WAS_DISABLED"

# 在替换任何文件或 job 前拒绝占用目标端口的非当前 Web job，避免把安装
# 表面上报告为成功却留下一个无法监听的服务。
LISTENER_PIDS="$(port_listener_pids "$PORT")"
if [ -n "$LISTENER_PIDS" ]; then
  CURRENT_WEB_PID="$(job_pid "$WEB_JOB" || true)"
  if [ -z "$CURRENT_WEB_PID" ] || [ "$LISTENER_PIDS" != "$CURRENT_WEB_PID" ]; then
    die "端口 $PORT 已被其他进程占用（PID: $(printf '%s' "$LISTENER_PIDS" | tr '\n' ' ')）。请先停止该进程"
  fi
fi

job_is_loaded "$MENUBAR_JOB" && MENUBAR_WAS_LOADED=1
job_is_loaded "$LOGROTATE_JOB" && LOGROTATE_WAS_LOADED=1

# 保存安装器明确拥有的文件。任何切换失败都会尽力恢复这些文件以及三个
# job 的加载/运行/disabled 状态，不触碰 sessions、storages 或其他 dsh 数据。
BACKUP_DIR="$STAGE_DIR/backup"
run_or_die "创建回滚目录失败" mkdir -p "$BACKUP_DIR/managed"
if [ -d "$APP_DIR" ]; then
  run_or_die "备份现有 DShMenu.app 失败" /usr/bin/ditto --norsrc "$APP_DIR" "$BACKUP_DIR/app"
fi
for backup_label in "$WEB_LABEL" "$MENUBAR_LABEL" "$LOGROTATE_LABEL"; do
  backup_plist="$LAUNCH_AGENTS/$backup_label.plist"
  if [ -f "$backup_plist" ]; then
    run_or_die "备份 $backup_plist 失败" cp "$backup_plist" "$BACKUP_DIR/$backup_label.plist"
  fi
done
for managed_name in node dsh npm npx pnpm corepack rotate_logs.sh; do
  if [ -e "$STABLE_BIN/$managed_name" ] || [ -L "$STABLE_BIN/$managed_name" ]; then
    run_or_die "备份 $STABLE_BIN/$managed_name 失败" \
      cp -P "$STABLE_BIN/$managed_name" "$BACKUP_DIR/managed/$managed_name"
  fi
done
[ ! -f "$MANAGED_MARKER" ] || touch "$BACKUP_DIR/managed-marker"

# ---------- 5. 安装已通过预检的文件 ----------
echo "==> 安装已预检文件"
if [ -d "$MANAGED_ROOT" ] && [ ! -f "$MANAGED_MARKER" ]; then
  for managed_name in node dsh npm npx pnpm corepack rotate_logs.sh; do
    [ ! -e "$STABLE_BIN/$managed_name" ] && [ ! -L "$STABLE_BIN/$managed_name" ] || \
      die "$MANAGED_ROOT 不是已标记的 DShMenu 管理目录，拒绝覆盖 $STABLE_BIN/$managed_name"
  done
fi
MUTATION_STARTED=1
run_or_die "创建安装目录失败" mkdir -p "$HOME/Applications" "$LAUNCH_AGENTS" "$LOG_DIR" "$STABLE_BIN"
run_or_die "创建运行目录所有权标记失败" touch "$MANAGED_MARKER"
run_or_die "更新 node 稳定软链失败" ln -sf "$NODE" "$STABLE_BIN/node"
run_or_die "更新 dsh 稳定软链失败" ln -sf "$DSH_BIN" "$STABLE_BIN/dsh"
for b in npm npx pnpm corepack; do
  if [ -x "$NODE_DIR/$b" ]; then
    run_or_die "更新 $b 稳定软链失败" ln -sf "$NODE_DIR/$b" "$STABLE_BIN/$b"
  fi
done
run_or_die "安装日志轮转脚本失败" cp "$STAGE_DIR/rotate_logs.sh" "$STABLE_BIN/rotate_logs.sh"
run_or_die "设置日志轮转脚本权限失败" chmod +x "$STABLE_BIN/rotate_logs.sh"
if [ ! -e "$CONFIG_PLIST" ]; then
  run_or_die "安装默认端口配置失败" cp "$STAGE_DIR/DShMenu.config.plist" "$CONFIG_PLIST"
  CONFIG_CREATED=1
fi

if [ -e "$APP_DIR" ]; then
  run_or_die "移除旧 DShMenu.app 失败" rm -rf "$APP_DIR"
fi
run_or_die "安装 DShMenu.app 失败" /usr/bin/ditto --norsrc "$STAGE_DIR/DShMenu.app" "$APP_DIR"
run_or_die "清理已安装 App 扩展属性失败" /usr/bin/xattr -cr "$APP_DIR"
run_or_die "已安装 App 签名验证失败" \
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
run_or_die "安装 Web LaunchAgent plist 失败" cp "$STAGE_DIR/$WEB_LABEL.plist" "$WEB_PLIST"
run_or_die "安装菜单栏 LaunchAgent plist 失败" cp "$STAGE_DIR/$MENUBAR_LABEL.plist" "$MENUBAR_PLIST"
run_or_die "安装日志轮转 LaunchAgent plist 失败" cp "$STAGE_DIR/$LOGROTATE_LABEL.plist" "$LOGROTATE_PLIST"

# ---------- 6. 切换 Web job，同时保持原 loaded/running/disabled 语义 ----------
echo "==> 切换 Web LaunchAgent"
if [ "$WEB_WAS_LOADED" -eq 1 ]; then
  run_or_die "卸载旧 Web LaunchAgent 失败" launchctl bootout "$WEB_JOB"
  run_or_die "旧 Web LaunchAgent 未能完全卸载" wait_for_job_unloaded "$WEB_JOB"
fi

if [ "$WEB_IS_FRESH" -eq 1 ] || [ "$WEB_WAS_LOADED" -eq 1 ]; then
  if [ "$WEB_WAS_DISABLED" -eq 1 ] && [ "$WEB_IS_FRESH" -eq 0 ]; then
    run_or_die "临时启用 Web LaunchAgent 失败" launchctl enable "$WEB_JOB"
    WEB_TEMP_ENABLED=1
  else
    run_or_die "把 Web LaunchAgent 归一为 enabled 失败" launchctl enable "$WEB_JOB"
  fi
  run_or_die "加载 Web LaunchAgent 失败（plist: ${WEB_PLIST}）" bootstrap_job "$DOMAIN" "$WEB_PLIST"
  if [ "$WEB_TEMP_ENABLED" -eq 1 ]; then
    run_or_die "恢复 Web LaunchAgent 的 disabled 偏好失败" launchctl disable "$WEB_JOB"
    WEB_TEMP_ENABLED=0
  fi

  if [ "$WEB_IS_FRESH" -eq 1 ] || [ "$WEB_WAS_RUNNING" -eq 1 ]; then
    if [ "$(job_state "$WEB_JOB" || true)" != "running" ]; then
      run_or_die "启动 Web LaunchAgent 失败" launchctl kickstart "$WEB_JOB"
    fi
    run_or_die "Web LaunchAgent 未进入 running 状态；请查看 $LOG_DIR/dsh-web.err.log" \
      wait_for_job_state "$WEB_JOB" running 100
  else
    launchctl kill SIGTERM "$WEB_JOB" >/dev/null 2>&1 || true
    run_or_die "Web LaunchAgent 未能恢复安装前的停止状态" wait_for_job_not_running "$WEB_JOB" 100
  fi
else
  echo "  原 Web job 未加载；保留为未加载状态"
fi

# ---------- 7. 菜单栏只由 launchd 拉起，避免 open 抢锁 ----------
echo "==> 切换菜单栏 LaunchAgent"
if job_is_loaded "$MENUBAR_JOB"; then
  run_or_die "卸载旧菜单栏 LaunchAgent 失败" launchctl bootout "$MENUBAR_JOB"
  run_or_die "旧菜单栏 LaunchAgent 未能完全卸载" wait_for_job_unloaded "$MENUBAR_JOB"
fi
pkill -x DShMenu 2>/dev/null || true
run_or_die "旧 DShMenu 进程未能退出" wait_for_process_exit DShMenu
run_or_die "启用菜单栏 LaunchAgent 失败" launchctl enable "$MENUBAR_JOB"
run_or_die "加载菜单栏 LaunchAgent 失败" bootstrap_job "$DOMAIN" "$MENUBAR_PLIST"
run_or_die "菜单栏 LaunchAgent 未进入 running 状态" wait_for_job_state "$MENUBAR_JOB" running 100
MENUBAR_PID="$(job_pid "$MENUBAR_JOB" || true)"
[[ "$MENUBAR_PID" =~ ^[0-9]+$ ]] || die "菜单栏 LaunchAgent 已加载但没有有效 PID"
echo "  菜单栏由 launchd 管理，pid=$MENUBAR_PID"

# ---------- 8. 日志轮转始终保持加载 ----------
echo "==> 切换日志轮转 LaunchAgent"
if job_is_loaded "$LOGROTATE_JOB"; then
  run_or_die "卸载旧日志轮转 LaunchAgent 失败" launchctl bootout "$LOGROTATE_JOB"
  run_or_die "旧日志轮转 LaunchAgent 未能完全卸载" wait_for_job_unloaded "$LOGROTATE_JOB"
fi
run_or_die "启用日志轮转 LaunchAgent 失败" launchctl enable "$LOGROTATE_JOB"
run_or_die "加载日志轮转 LaunchAgent 失败" bootstrap_job "$DOMAIN" "$LOGROTATE_PLIST"
job_is_loaded "$LOGROTATE_JOB" || die "日志轮转 LaunchAgent 加载后无法查询"

echo "=============================================="
echo " 安装完成"
echo "  - Web 地址: http://127.0.0.1:$PORT"
echo "  - 端口配置: $CONFIG_PLIST"
echo "  - 服务日志: $LOG_DIR/dsh-web.{out,err}.log"
echo "  - 菜单栏: 左键=打开 dsh 页面, 右键=控制菜单"
if [ "$WEB_IS_FRESH" -eq 1 ] || [ "$WEB_WAS_RUNNING" -eq 1 ]; then
  if wait_for_dsh_identity "$PORT" 100; then
    echo "  - DSh 身份探活通过: http://127.0.0.1:$PORT"
  else
    echo "  - 警告: Web job 已启动，但 DSh 身份探活未通过；请查看错误日志" >&2
  fi
elif [ "$WEB_WAS_INSTALLED" -eq 1 ] && [ "$WEB_WAS_RUNNING" -eq 0 ]; then
  echo "  - Web 服务按安装前状态保持停止"
else
  echo "  - Web 服务当前未运行"
fi
echo "=============================================="
