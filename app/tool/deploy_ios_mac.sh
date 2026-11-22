#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/filemanager/ios_mac.env"
CLI_CONFIG=""
CLI_HOST=""
CLI_PORT=""
CLI_REMOTE_DIR=""
DO_SYNC=1
FORCE_REFRESH=0
SETUP_ONLY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Sync source changes to a paired Mac build host, build iOS Release inside the
Mac Aqua GUI session (using the unlocked login keychain), and wirelessly
install onto the paired iPhone via CoreDevice (devicectl).

Configuration precedence: CLI flags > environment variables > config file
Config file default: $DEFAULT_CONFIG_FILE
Supported env/config keys:
  FM_IOS_MAC_HOST        Mac SSH target (e.g. user@mac-host)
  FM_IOS_MAC_PORT        Mac SSH port (default: 22)
  FM_IOS_MAC_REMOTE_DIR  Remote repository path on Mac (default: \$HOME/project/filemanager-port)
  FM_IOS_MAC_CONFIG      Override path to env config file

Options:
  --host <user@host>       Mac SSH target
  --port <port>            Mac SSH port (default: 22)
  --remote-dir <path>      Remote repository path on Mac
  --config <path>          Path to env config file
  --no-sync                Skip rsync source sync to Mac
  --force-refresh-profile  Force regeneration of provisioning profile even if valid
  --setup-only             Sync worker & install/refresh Mac LaunchAgents without building
  -h, --help               Show this help message
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      CLI_HOST="${2:?--host requires a value}"
      shift 2
      ;;
    --port)
      CLI_PORT="${2:?--port requires a value}"
      shift 2
      ;;
    --remote-dir)
      CLI_REMOTE_DIR="${2:?--remote-dir requires a value}"
      shift 2
      ;;
    --config)
      CLI_CONFIG="${2:?--config requires a value}"
      shift 2
      ;;
    --no-sync)
      DO_SYNC=0
      shift
      ;;
    --force-refresh-profile)
      FORCE_REFRESH=1
      shift
      ;;
    --setup-only)
      SETUP_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

CONFIG_FILE="${CLI_CONFIG:-${FM_IOS_MAC_CONFIG:-$DEFAULT_CONFIG_FILE}}"
CFG_HOST=""
CFG_PORT=""
CFG_REMOTE_DIR=""

strip_quotes_and_ws() {
  local val="$1"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  if [ "${#val}" -ge 2 ]; then
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
  fi
  printf '%s' "$val"
}

if [ -f "$CONFIG_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ''|\#*) continue ;;
    esac
    case "$line" in
      *=*)
        key="$(strip_quotes_and_ws "${line%%=*}")"
        val="$(strip_quotes_and_ws "${line#*=}")"
        case "$key" in
          FM_IOS_MAC_HOST) CFG_HOST="$val" ;;
          FM_IOS_MAC_PORT) CFG_PORT="$val" ;;
          FM_IOS_MAC_REMOTE_DIR) CFG_REMOTE_DIR="$val" ;;
        esac
        ;;
    esac
  done < "$CONFIG_FILE"
fi

MAC_HOST="${CLI_HOST:-${FM_IOS_MAC_HOST:-$CFG_HOST}}"
MAC_PORT="${CLI_PORT:-${FM_IOS_MAC_PORT:-${CFG_PORT:-22}}}"
REMOTE_DIR="${CLI_REMOTE_DIR:-${FM_IOS_MAC_REMOTE_DIR:-$CFG_REMOTE_DIR}}"

if [ -z "$MAC_HOST" ]; then
  cat >&2 <<EOF
ERROR: Mac SSH target is not configured.
Provide --host <user@host>, set FM_IOS_MAC_HOST, or create $CONFIG_FILE with:
  FM_IOS_MAC_HOST=<user@host>
  FM_IOS_MAC_PORT=22
  FM_IOS_MAC_REMOTE_DIR=/Users/<user>/project/filemanager-port
EOF
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -p "$MAC_PORT")

if [ -z "$REMOTE_DIR" ]; then
  REMOTE_DIR="$(ssh "${SSH_OPTS[@]}" "$MAC_HOST" 'printf "%s\n" "$HOME/project/filemanager-port"')"
fi

DEPLOY_LABEL="com.github.th997.filemanager.ios-deploy"
RENEW_LABEL="com.github.th997.filemanager.ios-renew"

if [ "$DO_SYNC" -eq 1 ]; then
  echo "=== [1/3] Syncing source files to $MAC_HOST:$REMOTE_DIR ==="
  cd "$REPO_ROOT"
  rsync -azcR \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=15 -p $MAC_PORT" \
    --exclude='GeneratedPluginRegistrant.h' \
    --exclude='GeneratedPluginRegistrant.m' \
    --exclude='.DS_Store' \
    --exclude='__pycache__/' \
    --exclude='packages/**/.cache/' \
    --exclude='packages/**/Frameworks/' \
    --exclude='packages/**/Headers/' \
    --exclude='packages/**/build/' \
    app/lib \
    app/ios/Runner \
    app/packages \
    app/test \
    app/tool \
    app/pubspec.yaml \
    app/l10n.yaml \
    rust/Cargo.toml \
    rust/Cargo.lock \
    rust/crates \
    "$MAC_HOST:$REMOTE_DIR/"
else
  echo "=== [1/3] Skipping source sync (--no-sync) ==="
fi

echo "=== [2/3] Installing/verifying Mac Aqua LaunchAgents ==="
ssh "${SSH_OPTS[@]}" "$MAC_HOST" 'bash -s' -- "$REMOTE_DIR" "$DEPLOY_LABEL" "$RENEW_LABEL" <<'REMOTE_SETUP'
set -euo pipefail

REMOTE_DIR="$1"
DEPLOY_LABEL="$2"
RENEW_LABEL="$3"
UID_NUM="$(id -u)"
AGENTS_DIR="$HOME/Library/LaunchAgents"
LOGS_DIR="$HOME/Library/Logs"
WORKER_PATH="$REMOTE_DIR/app/tool/ios_mac_worker.sh"

if [ ! -f "$WORKER_PATH" ]; then
  echo "ERROR: Worker script missing on Mac: $WORKER_PATH" >&2
  exit 1
fi
chmod +x "$WORKER_PATH"
mkdir -p "$AGENTS_DIR" "$LOGS_DIR"

install_agent() {
  local label="$1"
  local plist_path="$AGENTS_DIR/${label}.plist"
  local tmp_plist
  tmp_plist="$(mktemp "/tmp/${label}.XXXXXX.plist")"
  cat > "$tmp_plist"
  plutil -lint "$tmp_plist" >/dev/null

  local needs_reload=0
  if [ ! -f "$plist_path" ] || ! cmp -s "$tmp_plist" "$plist_path"; then
    mv "$tmp_plist" "$plist_path"
    needs_reload=1
  else
    rm -f "$tmp_plist"
  fi

  if ! launchctl print "gui/$UID_NUM/$label" >/dev/null 2>&1; then
    needs_reload=1
  fi

  if [ "$needs_reload" -eq 1 ]; then
    launchctl bootout "gui/$UID_NUM/$label" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID_NUM" "$plist_path"
    echo "[launchd] Loaded gui/$UID_NUM/$label"
  else
    echo "[launchd] Already loaded gui/$UID_NUM/$label"
  fi
}

install_agent "$DEPLOY_LABEL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$DEPLOY_LABEL</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$WORKER_PATH</string>
    <string>deploy</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/tmp/fm-ios-deploy-agent.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/fm-ios-deploy-agent.log</string>
</dict>
</plist>
EOF

install_agent "$RENEW_LABEL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$RENEW_LABEL</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$WORKER_PATH</string>
    <string>renew</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>5</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$LOGS_DIR/filemanager-ios-renew.log</string>
  <key>StandardErrorPath</key>
  <string>$LOGS_DIR/filemanager-ios-renew.log</string>
</dict>
</plist>
EOF
REMOTE_SETUP

if [ "$SETUP_ONLY" -eq 1 ]; then
  echo "=== Setup complete (--setup-only) ==="
  exit 0
fi

echo "=== [3/3] Building & wirelessly installing iOS app via Mac Aqua session ==="
ssh "${SSH_OPTS[@]}" "$MAC_HOST" 'bash -s' -- "$FORCE_REFRESH" "$DEPLOY_LABEL" <<'REMOTE_RUN'
set -euo pipefail

FORCE_REFRESH="$1"
DEPLOY_LABEL="$2"
UID_NUM="$(id -u)"
LOG_FILE="/tmp/fm-ios-deploy.log"
EXIT_FILE="/tmp/fm-ios-deploy.exit"
FLAGS_FILE="/tmp/fm-ios-deploy.flags"
AGENT_LOG="/tmp/fm-ios-deploy-agent.log"

rm -f "$EXIT_FILE" "$FLAGS_FILE" "$AGENT_LOG"
: > "$LOG_FILE"
if [ "$FORCE_REFRESH" = "1" ]; then
  printf 'FORCE_REFRESH=1\n' > "$FLAGS_FILE"
fi

launchctl kickstart -k "gui/$UID_NUM/$DEPLOY_LABEL"

/usr/bin/python3 - "$LOG_FILE" "$EXIT_FILE" "$AGENT_LOG" <<'PY_WATCH'
import os, sys, time

log_path, exit_path, agent_log_path = sys.argv[1:4]
offset = 0
start = time.time()
timeout = 900.0
warned_agent = False

def drain():
    global offset
    if not os.path.exists(log_path):
        return
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        f.seek(offset)
        chunk = f.read()
        if chunk:
            sys.stdout.write(chunk)
            sys.stdout.flush()
            offset = f.tell()

while True:
    drain()
    if os.path.exists(exit_path):
        time.sleep(0.2)
        drain()
        with open(exit_path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read().strip()
        try:
            rc = int(raw)
        except ValueError:
            rc = 1
        sys.exit(rc)

    elapsed = time.time() - start
    if not warned_agent and offset == 0 and elapsed > 15.0 and os.path.exists(agent_log_path):
        with open(agent_log_path, "r", encoding="utf-8", errors="replace") as f:
            agent_err = f.read().strip()
        if agent_err:
            sys.stderr.write("[launchd agent output]\n" + agent_err + "\n")
            sys.stderr.flush()
            warned_agent = True

    if elapsed > timeout:
        sys.stderr.write(f"ERROR: Timed out after {int(timeout)}s waiting for iOS deploy.\n")
        sys.exit(124)

    time.sleep(0.4)
PY_WATCH
REMOTE_RUN
