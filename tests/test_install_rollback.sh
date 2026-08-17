#!/bin/bash
# Exercise a fresh-install failure entirely inside a temporary HOME with a
# stateful launchctl shim. No production App, LaunchAgent, or DSH_HOME is used.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dshmenu-rollback.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
FAKE_STATE="$TMP_ROOT/state"
FAKE_HOME="$TMP_ROOT/home"
mkdir -p "$FAKE_BIN" "$FAKE_STATE" "$FAKE_HOME/work"
REAL_MENU_PID_BEFORE="$(/usr/bin/pgrep -x DShMenu 2>/dev/null || true)"

cat > "$FAKE_BIN/node" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$FAKE_BIN/dsh" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  echo 0.0.0-test
  exit 0
fi
exit 0
EOF

cat > "$FAKE_BIN/lsof" <<'EOF'
#!/bin/sh
exit 1
EOF

cat > "$FAKE_BIN/curl" <<'EOF'
#!/bin/sh
exit 1
EOF

# The production installer deliberately cleans up stale DShMenu processes.
# These shims keep the isolated test from ever targeting the user's real app.
cat > "$FAKE_BIN/pkill" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$FAKE_BIN/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF

cat > "$FAKE_BIN/launchctl" <<'EOF'
#!/bin/bash
set -euo pipefail
state_dir="${FAKE_STATE:?}"
command_name="${1:-}"
target="${2:-}"
label="${target##*/}"
case "$command_name" in
  print)
    [ -f "$state_dir/$label" ] || exit 113
    echo "state = $(cat "$state_dir/$label")"
    echo "pid = 4242"
    ;;
  print-disabled)
    echo "disabled services = {}"
    ;;
  bootstrap)
    plist="${3:?}"
    label="$(/usr/bin/plutil -extract Label raw -o - "$plist")"
    if [ "$label" = "com.zjr.dsh-menubar" ]; then
      echo "injected menu bootstrap failure" >&2
      exit 9
    fi
    echo running > "$state_dir/$label"
    ;;
  bootout)
    rm -f "$state_dir/$label"
    ;;
  kickstart)
    target="${@: -1}"
    echo running > "$state_dir/${target##*/}"
    ;;
  kill)
    target="${@: -1}"
    echo stopped > "$state_dir/${target##*/}"
    ;;
  enable|disable)
    ;;
  *)
    echo "unexpected launchctl command: $*" >&2
    exit 64
    ;;
esac
EOF

chmod +x \
  "$FAKE_BIN/node" \
  "$FAKE_BIN/dsh" \
  "$FAKE_BIN/lsof" \
  "$FAKE_BIN/curl" \
  "$FAKE_BIN/pkill" \
  "$FAKE_BIN/pgrep" \
  "$FAKE_BIN/launchctl"

set +e
HOME="$FAKE_HOME" \
DSH_HOME="$FAKE_HOME/.dsh" \
DSH_WORKDIR="$FAKE_HOME/work" \
FAKE_STATE="$FAKE_STATE" \
PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  /bin/bash "$ROOT/install.sh" > "$TMP_ROOT/install.log" 2>&1
install_code=$?
set -e

REAL_MENU_PID_AFTER="$(/usr/bin/pgrep -x DShMenu 2>/dev/null || true)"
[ "$REAL_MENU_PID_AFTER" = "$REAL_MENU_PID_BEFORE" ] || {
  echo "FAIL: isolated test changed the real DShMenu process set" >&2
  echo "before: ${REAL_MENU_PID_BEFORE:-none}; after: ${REAL_MENU_PID_AFTER:-none}" >&2
  exit 1
}

[ "$install_code" -ne 0 ] || {
  echo "FAIL: injected menu bootstrap failure did not fail install" >&2
  sed -n '1,260p' "$TMP_ROOT/install.log" >&2
  exit 1
}

for unexpected in \
  "$FAKE_HOME/Applications/DShMenu.app" \
  "$FAKE_HOME/Library/LaunchAgents/com.zjr.dsh-web.plist" \
  "$FAKE_HOME/Library/LaunchAgents/com.zjr.dsh-menubar.plist" \
  "$FAKE_HOME/Library/LaunchAgents/com.zjr.dsh-logrotate.plist" \
  "$FAKE_HOME/.dsh/DShMenu.config.plist" \
  "$FAKE_HOME/.dsh/dshmenu/.managed-by-dshmenu"; do
  [ ! -e "$unexpected" ] || {
    echo "FAIL: rollback left $unexpected" >&2
    sed -n '1,240p' "$TMP_ROOT/install.log" >&2
    exit 1
  }
done

for label in com.zjr.dsh-web com.zjr.dsh-menubar com.zjr.dsh-logrotate; do
  [ ! -e "$FAKE_STATE/$label" ] || {
    echo "FAIL: rollback left fake job $label loaded" >&2
    exit 1
  }
done

grep -q '尝试恢复安装前状态' "$TMP_ROOT/install.log" || {
  echo "FAIL: rollback was not reported" >&2
  exit 1
}

echo "PASS: fresh-install failure rolled back files and jobs"
