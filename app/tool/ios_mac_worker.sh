#!/bin/bash
set -euo pipefail

if [ -z "${HOME:-}" ]; then
  HOME="$(eval echo "~$(id -un)")"
fi
export HOME
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin:$HOME/.cargo/bin:$PATH"

MODE="${1:-deploy}"
case "$MODE" in
  deploy|renew) ;;
  *)
    echo "Usage: $0 [deploy|renew]" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_REPO_DIR="${FM_REPO_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FM_APP_DIR="$FM_REPO_DIR/app"
FM_BUNDLE_ID="${FM_BUNDLE_ID:-com.github.th997.filemanager}"
FM_RENEW_ALWAYS="${FM_RENEW_ALWAYS:-1}"
FM_RENEW_THRESHOLD_HOURS="${FM_RENEW_THRESHOLD_HOURS:-48}"
FM_IOS_DEVICE_ID="${FM_IOS_DEVICE_ID:-}"

LOG_FILE="/tmp/fm-ios-deploy.log"
EXIT_FILE="/tmp/fm-ios-deploy.exit"
FLAGS_FILE="/tmp/fm-ios-deploy.flags"
LOCK_DIR="/tmp/fm-ios-worker.lock"

LOCK_OWNED=0
BUILD_SUCCEEDED=0
BACKUP_DIR=""

if [ "$MODE" = "deploy" ]; then
  rm -f "$EXIT_FILE"
  : > "$LOG_FILE"
  exec > "$LOG_FILE" 2>&1
fi

restore_backed_up_profiles() {
  if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
    return 0
  fi
  if [ -f "$BACKUP_DIR/manifest.tsv" ]; then
    while IFS="$(printf '\t')" read -r backup_path orig_path; do
      if [ -n "$backup_path" ] && [ -n "$orig_path" ] && [ -f "$backup_path" ]; then
        mkdir -p "$(dirname "$orig_path")"
        mv "$backup_path" "$orig_path"
        echo "[profile] Restored profile: $orig_path"
      fi
    done < "$BACKUP_DIR/manifest.tsv"
  fi
  rm -rf "$BACKUP_DIR"
  BACKUP_DIR=""
}

cleanup() {
  local rc=$?
  set +e
  if [ "$BUILD_SUCCEEDED" -ne 1 ]; then
    restore_backed_up_profiles
  elif [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
  fi
  if [ "$LOCK_OWNED" -eq 1 ] && [ -d "$LOCK_DIR" ]; then
    rm -rf "$LOCK_DIR"
  fi
  if [ "$MODE" = "deploy" ]; then
    printf '%s\n' "$rc" > "${EXIT_FILE}.tmp" && mv "${EXIT_FILE}.tmp" "$EXIT_FILE"
  fi
}
trap cleanup EXIT

acquire_lock() {
  local waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [ -f "$LOCK_DIR/pid" ]; then
      local old_pid
      old_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
      if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
        echo "[lock] Removing stale lock for dead PID $old_pid"
        rm -rf "$LOCK_DIR"
        continue
      fi
    fi
    if [ "$waited" -ge 30 ]; then
      echo "[lock] Another iOS worker instance is already running (lock=$LOCK_DIR)." >&2
      exit 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  LOCK_OWNED=1
}

inspect_profile_hours() {
  local profile_path="$1"
  [ -f "$profile_path" ] || return 1
  security cms -D -i "$profile_path" 2>/dev/null | /usr/bin/python3 -c '
import datetime, plistlib, sys
raw = sys.stdin.buffer.read()
if not raw:
    sys.exit(1)
data = plistlib.loads(raw)
exp = data.get("ExpirationDate")
cre = data.get("CreationDate")
if exp is None:
    sys.exit(1)
if exp.tzinfo is None:
    exp = exp.replace(tzinfo=datetime.timezone.utc)
if cre is not None and cre.tzinfo is None:
    cre = cre.replace(tzinfo=datetime.timezone.utc)
now = datetime.datetime.now(datetime.timezone.utc)
hours = (exp - now).total_seconds() / 3600.0
app_id = data.get("Entitlements", {}).get("application-identifier", "")
name = data.get("Name", "")
cre_s = cre.isoformat() if cre else ""
print(f"{hours:.2f}|{exp.isoformat()}|{cre_s}|{name}|{app_id}")
'
}

profile_matches_bundle() {
  local app_id="$1"
  local name="$2"
  case "$app_id" in
    "$FM_BUNDLE_ID"|*."$FM_BUNDLE_ID") return 0 ;;
  esac
  case "$name" in
    *"$FM_BUNDLE_ID"*) return 0 ;;
  esac
  return 1
}

is_hours_below_threshold() {
  local hours="$1"
  /usr/bin/python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$hours" "$FM_RENEW_THRESHOLD_HOURS"
}

rotate_expiring_profiles() {
  local force_refresh="$1"
  local idx=0
  local dir
  for dir in \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles"
  do
    [ -d "$dir" ] || continue
    local p
    for p in "$dir"/*.mobileprovision; do
      [ -f "$p" ] || continue
      local info
      info="$(inspect_profile_hours "$p" || true)"
      [ -n "$info" ] || continue
      local hours exp cre name app_id
      IFS='|' read -r hours exp cre name app_id <<< "$info"
      if ! profile_matches_bundle "$app_id" "$name"; then
        continue
      fi
      if [ "$force_refresh" = "1" ] || is_hours_below_threshold "$hours"; then
        if [ -z "$BACKUP_DIR" ]; then
          BACKUP_DIR="$(mktemp -d /tmp/fm-ios-profile-backup.XXXXXX)"
        fi
        idx=$((idx + 1))
        local backup_file="$BACKUP_DIR/${idx}_$(basename "$p")"
        mv "$p" "$backup_file"
        printf '%s\t%s\n' "$backup_file" "$p" >> "$BACKUP_DIR/manifest.tsv"
        echo "[profile] Moved expiring/stale profile (${hours}h left, exp=$exp): $p"
      else
        echo "[profile] Keeping valid profile (${hours}h left, exp=$exp): $p"
      fi
    done
  done
}

find_best_installed_profile_hours() {
  local embedded="$FM_APP_DIR/build/ios/iphoneos/Runner.app/embedded.mobileprovision"
  if [ -f "$embedded" ]; then
    local info
    info="$(inspect_profile_hours "$embedded" || true)"
    if [ -n "$info" ]; then
      printf '%s\n' "$info"
      return 0
    fi
  fi

  local best_info=""
  local best_hours=""
  local dir
  for dir in \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles"
  do
    [ -d "$dir" ] || continue
    local p
    for p in "$dir"/*.mobileprovision; do
      [ -f "$p" ] || continue
      local info
      info="$(inspect_profile_hours "$p" || true)"
      [ -n "$info" ] || continue
      local hours exp cre name app_id
      IFS='|' read -r hours exp cre name app_id <<< "$info"
      if ! profile_matches_bundle "$app_id" "$name"; then
        continue
      fi
      if [ -z "$best_hours" ] || /usr/bin/python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)' "$hours" "$best_hours"; then
        best_hours="$hours"
        best_info="$info"
      fi
    done
  done

  if [ -n "$best_info" ]; then
    printf '%s\n' "$best_info"
    return 0
  fi
  return 1
}

find_target_device() {
  local tmp_json
  tmp_json="$(mktemp /tmp/fm-ios-devices.XXXXXX.json)"
  if ! xcrun devicectl list devices --json-output "$tmp_json" >/dev/null 2>&1; then
    rm -f "$tmp_json"
    return 1
  fi
  local selected
  selected="$(/usr/bin/python3 -c '
import json, sys

path = sys.argv[1]
preferred = sys.argv[2].strip()
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

devices = data.get("result", {}).get("devices", [])
candidates = []
for dev in devices:
    hw = dev.get("hardwareProperties", {})
    dp = dev.get("deviceProperties", {})
    cp = dev.get("connectionProperties", {})
    if hw.get("platform") != "iOS" or hw.get("reality") != "physical":
        continue
    if cp.get("pairingState") != "paired":
        continue
    tunnel_state = cp.get("tunnelState") or ""
    if tunnel_state == "unavailable":
        continue
    ident = dev.get("identifier") or ""
    udid = hw.get("udid") or ""
    name = dp.get("name") or "iPhone"
    model = hw.get("marketingName") or hw.get("productType") or "iOS"
    transport = cp.get("transportType") or ""
    if preferred and preferred not in (ident, udid, name):
        continue
    score = (
        1 if transport == "wired" else 0,
        1 if tunnel_state == "connected" else 0,
        1 if transport == "localNetwork" else 0,
    )
    candidates.append((score, ident, name, model, transport))

if not candidates:
    sys.exit(1)
candidates.sort(reverse=True)
_, ident, name, model, transport = candidates[0]
print(f"{ident}|{name}|{model}|{transport}")
' "$tmp_json" "$FM_IOS_DEVICE_ID" 2>/dev/null || true)"
  rm -f "$tmp_json"
  if [ -n "$selected" ]; then
    printf '%s\n' "$selected"
    return 0
  fi
  return 1
}

build_ios_release() {
  cd "$FM_APP_DIR"
  local needs_pub_get=0
  local needs_pod_install=0
  if [ ! -f ".dart_tool/package_config.json" ] || [ "pubspec.yaml" -nt ".dart_tool/package_config.json" ]; then
    needs_pub_get=1
    needs_pod_install=1
  fi
  if [ ! -f "ios/Pods/Manifest.lock" ] || [ "pubspec.yaml" -nt "ios/Pods/Manifest.lock" ] || [ "packages/media_kit_libs_ios_video/ios/Makefile" -nt "ios/Pods/Manifest.lock" ]; then
    needs_pod_install=1
  fi
  if [ "$needs_pub_get" -eq 1 ]; then
    echo "[build] Running flutter pub get..."
    flutter pub get
  fi
  if [ "$needs_pod_install" -eq 1 ]; then
    echo "[build] Running CocoaPods pod install..."
    (cd ios && pod install && touch Pods/Manifest.lock)
  fi
  echo "[build] Building iOS Release in $FM_APP_DIR..."
  if ! flutter build ios --release --no-pub; then
    echo "[build] --no-pub failed, retrying with flutter build ios --release..."
    flutter build ios --release
  fi
  BUILD_SUCCEEDED=1
  if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    rm -rf "$BACKUP_DIR"
    BACKUP_DIR=""
  fi
}

log_embedded_profile() {
  local embedded="$FM_APP_DIR/build/ios/iphoneos/Runner.app/embedded.mobileprovision"
  if [ -f "$embedded" ]; then
    local info
    info="$(inspect_profile_hours "$embedded" || true)"
    if [ -n "$info" ]; then
      local hours exp cre name app_id
      IFS='|' read -r hours exp cre name app_id <<< "$info"
      echo "[profile] Embedded profile: $name ($app_id)"
      echo "[profile] CreationDate=$cre ExpirationDate=$exp (${hours}h remaining)"
    fi
  fi
}

install_to_device() {
  local device_info
  device_info="$(find_target_device || true)"
  if [ -z "$device_info" ]; then
    echo "[install] ERROR: No paired reachable iOS device found." >&2
    return 1
  fi
  local dev_id dev_name dev_model dev_transport
  IFS='|' read -r dev_id dev_name dev_model dev_transport <<< "$device_info"
  local app_bundle="$FM_APP_DIR/build/ios/iphoneos/Runner.app"
  echo "[install] Installing $app_bundle to $dev_name ($dev_model, $dev_transport, id=$dev_id)..."
  xcrun devicectl device install app --device "$dev_id" "$app_bundle"
  echo "[install] Done! Installed $FM_BUNDLE_ID on $dev_name."
}

acquire_lock

FORCE_REFRESH="${FORCE_REFRESH:-0}"
if [ "$MODE" = "deploy" ] && [ -f "$FLAGS_FILE" ]; then
  while IFS='=' read -r k v; do
    case "$k" in
      FORCE_REFRESH) FORCE_REFRESH="$v" ;;
    esac
  done < "$FLAGS_FILE"
  rm -f "$FLAGS_FILE"
fi

echo "=== FP File Manager iOS Worker ($MODE) ==="
echo "[env] Timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") Session=$(launchctl managername 2>/dev/null || echo unknown)"

if [ "$MODE" = "renew" ]; then
  DEVICE_CHECK="$(find_target_device || true)"
  if [ -z "$DEVICE_CHECK" ]; then
    echo "[renew] Target iPhone is currently offline/unreachable; skipping."
    exit 0
  fi

  if [ "$FM_RENEW_ALWAYS" = "1" ] || [ "$FORCE_REFRESH" = "1" ]; then
    echo "[renew] Daily renewal triggered; refreshing 7-day provisioning profile."
    rotate_expiring_profiles "1"
  else
    CURRENT_INFO="$(find_best_installed_profile_hours || true)"
    if [ -n "$CURRENT_INFO" ]; then
      IFS='|' read -r cur_hours cur_exp cur_cre cur_name cur_appid <<< "$CURRENT_INFO"
      if ! is_hours_below_threshold "$cur_hours"; then
        echo "[renew] Profile still valid (${cur_hours}h >= ${FM_RENEW_THRESHOLD_HOURS}h threshold, exp=$cur_exp). Skipping."
        exit 0
      fi
      echo "[renew] Profile nearing expiry (${cur_hours}h < ${FM_RENEW_THRESHOLD_HOURS}h, exp=$cur_exp)."
    else
      echo "[renew] No existing profile found; proceeding with refresh."
    fi
    rotate_expiring_profiles "0"
  fi

  build_ios_release
  log_embedded_profile
  install_to_device
  exit 0
fi

rotate_expiring_profiles "$FORCE_REFRESH"
build_ios_release
log_embedded_profile
install_to_device
