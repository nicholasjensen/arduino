#!/usr/bin/env bash
# phone-optimize.sh - speed and battery tuning for a NON-rooted Android phone over ADB.
#
# Runs from a computer with adb, or from Termux on the phone itself
# (see README.md). Every change is backed up first and can be undone with "revert".
#
# Usage:
#   ./phone-optimize.sh status             show the current values of every tweak
#   ./phone-optimize.sh apply              apply speed + battery tweaks
#   ./phone-optimize.sh speed              apply only the speed tweaks
#   ./phone-optimize.sh battery            apply only the battery tweaks
#   ./phone-optimize.sh revert             restore the values saved by the first apply
#   ./phone-optimize.sh restrict-apps      block background running for apps in restrict-apps.txt
#   ./phone-optimize.sh unrestrict-apps    undo restrict-apps
#
# Optional: ADB_SERIAL=<device id> picks one phone when several are connected.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HERE/settings-backup.txt"
APP_LIST="$HERE/restrict-apps.txt"
ANIM_SCALE="${ANIM_SCALE:-0.5}"   # 0.5 = twice as fast; 0 turns animations off

adb_sh() {
  if [ -n "${ADB_SERIAL:-}" ]; then adb -s "$ADB_SERIAL" shell "$@" </dev/null; else adb shell "$@" </dev/null; fi | tr -d '\r'
}

# "namespace key value" for every setting this script changes.
SPEED_SETTINGS="
global window_animation_scale $ANIM_SCALE
global transition_animation_scale $ANIM_SCALE
global animator_duration_scale $ANIM_SCALE
"
BATTERY_SETTINGS="
global wifi_scan_always_enabled 0
global ble_scan_always_enabled 0
global cached_apps_freezer enabled
global adaptive_battery_management_enabled 1
"

check_device() {
  command -v adb >/dev/null || { echo "adb not found. See README.md to install it." >&2; exit 1; }
  local state
  state="$( { if [ -n "${ADB_SERIAL:-}" ]; then adb -s "$ADB_SERIAL" get-state; else adb get-state; fi; } 2>&1 || true)"
  if [ "$state" != "device" ]; then
    echo "No authorized phone found (adb says: $state)." >&2
    echo "Turn on USB or wireless debugging and accept the prompt on the phone." >&2
    exit 1
  fi
  echo "Connected: $(adb_sh getprop ro.product.model) / Android $(adb_sh getprop ro.build.version.release)"
}

backup_once() {
  # Saves the original values only the first time, so revert always returns to stock.
  [ -f "$BACKUP" ] && return
  echo "$SPEED_SETTINGS$BATTERY_SETTINGS" | while read -r ns key _; do
    [ -z "$ns" ] && continue
    echo "$ns $key $(adb_sh settings get "$ns" "$key")"
  done > "$BACKUP"
  echo "Saved original values to $BACKUP"
}

apply_settings() {
  echo "$1" | while read -r ns key val; do
    [ -z "$ns" ] && continue
    adb_sh settings put "$ns" "$key" "$val"
    echo "  $key = $val"
  done
}

do_speed() {
  echo "== Speed =="
  apply_settings "$SPEED_SETTINGS"
  echo "  Compiling apps with the idle-time optimizer (can take several minutes)..."
  adb_sh cmd package bg-dexopt-job >/dev/null 2>&1 \
    && echo "  App compilation done." \
    || echo "  App compilation not supported on this Android version, skipped."
  echo "  Clearing app caches..."
  adb_sh pm trim-caches 999G >/dev/null 2>&1 && echo "  Caches cleared." || echo "  Cache clearing skipped."
}

do_battery() {
  echo "== Battery =="
  apply_settings "$BATTERY_SETTINGS"
  echo "  Background Wi-Fi and Bluetooth scanning are off (location still works, a little less precisely indoors)."
  echo "  Cached-app freezer takes effect after a reboot."
}

do_status() {
  echo "== Current values =="
  echo "$SPEED_SETTINGS$BATTERY_SETTINGS" | while read -r ns key _; do
    [ -z "$ns" ] && continue
    printf '  %-38s %s\n' "$key" "$(adb_sh settings get "$ns" "$key")"
  done
  echo "== Battery =="
  adb_sh dumpsys battery | grep -E '^\s*(level|temperature|health):' || true
  if [ -f "$APP_LIST" ]; then
    echo "== Background access for apps in restrict-apps.txt =="
    app_list | while read -r pkg; do
      printf '  %-45s %s\n' "$pkg" "$(adb_sh cmd appops get "$pkg" RUN_ANY_IN_BACKGROUND 2>/dev/null | head -n1)"
    done
  fi
}

do_revert() {
  [ -f "$BACKUP" ] || { echo "No backup at $BACKUP, nothing to revert." >&2; exit 1; }
  echo "== Reverting =="
  while read -r ns key val; do
    [ -z "$ns" ] && continue
    if [ "$val" = "null" ]; then
      adb_sh settings delete "$ns" "$key" >/dev/null
      echo "  $key -> default"
    else
      adb_sh settings put "$ns" "$key" "$val"
      echo "  $key -> $val"
    fi
  done < "$BACKUP"
  rm -f "$BACKUP"
  echo "Done. Reboot to fully restore the cached-app freezer setting."
}

app_list() { grep -vE '^\s*(#|$)' "$APP_LIST" | tr -d ' \r'; }

set_background() {  # $1 = ignore (restricted) | allow (normal)
  [ -f "$APP_LIST" ] || { echo "Create $APP_LIST first (one package name per line)." >&2; exit 1; }
  app_list | while read -r pkg; do
    if adb_sh pm path "$pkg" | grep -q '^package:'; then
      adb_sh cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND "$1"
      echo "  $pkg: background $( [ "$1" = ignore ] && echo restricted || echo allowed )"
    else
      echo "  $pkg: not installed, skipped"
    fi
  done
}

cmd="${1:-help}"
case "$cmd" in
  status)          check_device; do_status ;;
  apply)           check_device; backup_once; do_speed; do_battery; echo "Done. Reboot the phone to finish." ;;
  speed)           check_device; backup_once; do_speed ;;
  battery)         check_device; backup_once; do_battery ;;
  revert)          check_device; do_revert ;;
  restrict-apps)   check_device; echo "== Restricting background apps =="; set_background ignore ;;
  unrestrict-apps) check_device; echo "== Allowing background apps =="; set_background allow ;;
  *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
