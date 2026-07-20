#!/usr/bin/env bash
#
# android-recovery.sh
# ---------------------------------------------------------------------------
# Supported, non-bypass recovery helpers for an Android device you OWN.
# Wraps ADB for the "device still boots and is authorized" cases, and points you
# at the official remote/account flows for everything else.
#
# It NEVER attempts to defeat a lock screen, PIN/pattern, or Factory Reset
# Protection (FRP): the ADB actions only work when the screen is unlocked and
# this computer is already an authorized debugging host.
#
# Commands:
#   status               Show connected device, model, and authorization state
#   backup <dir>         adb backup (apps + data, where allowed) to <dir>
#   pull-media <dir>     Copy DCIM / Pictures / Download / Movies / Music to <dir>
#   find                 Open Google Find My Device in a browser
#   reset-guide          Print stock-recovery factory-reset steps (FRP-aware)
#   install-tools        Install adb (Android platform-tools)
#
# Usage:
#   chmod +x android-recovery.sh
#   ./android-recovery.sh status
#   ./android-recovery.sh backup ./out
#   ./android-recovery.sh pull-media ./out
#   ./android-recovery.sh --help
# ---------------------------------------------------------------------------

set -euo pipefail

c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_green=$'\033[1;32m'
c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'
log()  { printf '%s==>%s %s\n' "$c_blue"   "$c_reset" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$c_green"  "$c_reset" "$*"; }
warn() { printf '%s[!!]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[xx]%s %s\n' "$c_red"    "$c_reset" "$*" >&2; exit 1; }

print_help() {
  awk 'NR==1 {next} /^#/ {sub(/^#[[:space:]]?/, ""); print; next} {exit}' "$0"
  exit 0
}

have() { command -v "$1" >/dev/null 2>&1; }

install_tools() {
  log "Installing Android platform-tools (adb)"
  if have apt-get; then
    local sudo=""; [[ $EUID -ne 0 ]] && sudo="sudo"
    $sudo apt-get update -y
    $sudo apt-get install -y android-tools-adb
  elif have brew; then
    brew install --cask android-platform-tools
  else
    die "Install platform-tools manually: https://developer.android.com/tools/releases/platform-tools"
  fi
}

need_adb() {
  have adb || die "adb not found. Run: $0 install-tools"
}

# Authorization state: "device" (ok), "unauthorized", "none", or "offline".
device_state() {
  local line
  line=$(adb devices | awk 'NR>1 && NF>=2 {print $2; exit}')
  printf '%s' "${line:-none}"
}

require_authorized() {
  need_adb
  adb start-server >/dev/null 2>&1 || true
  local st; st=$(device_state)
  case "$st" in
    device) : ;;
    unauthorized)
      die "Device is UNAUTHORIZED. Unlock the phone and tap 'Allow' on the USB-debugging prompt, then retry." ;;
    none|"")
      die "No device detected. Enable USB debugging, use a data cable, and reconnect." ;;
    *)
      die "Device state '$st' — unlock the device and ensure USB debugging is authorized." ;;
  esac
}

cmd_status() {
  need_adb
  adb start-server >/dev/null 2>&1 || true
  local st; st=$(device_state)
  log "ADB device state: $st"
  if [[ "$st" == "device" ]]; then
    local brand model rel
    brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r' || true)
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)
    rel=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' || true)
    ok "Authorized: ${brand:-?} ${model:-?} (Android ${rel:-?})"
    echo "     You can run: $0 backup <dir>   |   $0 pull-media <dir>"
  else
    warn "Not authorized — see: $0 --help  and the SKILL.md troubleshooting."
  fi
}

cmd_backup() {
  local dir="${1:?usage: $0 backup <dir>}"
  require_authorized
  mkdir -p "$dir"
  local out
  out="$dir/adb-backup-$(date +%Y%m%d-%H%M%S).ab"
  warn "On the device: confirm the backup and (optionally) set a password."
  warn "Note: 'adb backup' is deprecated; many apps opt out. Prefer pull-media too."
  log "Backing up apps + shared storage to $out"
  adb backup -apk -shared -all -f "$out"
  if [[ -s "$out" ]]; then
    ok "Backup written: $out"
  else
    warn "Backup file is empty — the device or its apps may have refused backup."
  fi
}

cmd_pull_media() {
  local dir="${1:?usage: $0 pull-media <dir>}"
  require_authorized
  mkdir -p "$dir"
  local folder pulled=0
  for folder in DCIM Pictures Download Movies Music Documents; do
    if adb shell "[ -d /sdcard/$folder ]" 2>/dev/null; then
      log "Pulling /sdcard/$folder ..."
      if adb pull -a "/sdcard/$folder" "$dir/"; then
        pulled=$((pulled + 1))
      else
        warn "could not pull $folder"
      fi
    fi
  done
  if [[ $pulled -gt 0 ]]; then
    ok "Media copied under $dir/ ($pulled folder(s))"
  else
    warn "No media copied — no standard folders found or all pulls failed. Do NOT reset the device yet."
    return 1
  fi
}

open_url() {
  local url="$1"
  if have xdg-open; then xdg-open "$url" >/dev/null 2>&1 &
  elif have open; then open "$url" >/dev/null 2>&1 &
  elif have google-chrome; then google-chrome "$url" >/dev/null 2>&1 &
  else echo "$url"; fi
}

cmd_find() {
  log "Opening Google Find My Device (sign in with the account on the phone)"
  open_url "https://www.google.com/android/find"
  echo "     Samsung devices: https://smartthingsfind.samsung.com"
}

cmd_reset_guide() {
  cat <<EOF
${c_blue}Factory reset from stock recovery (device you own):${c_reset}
  1. Power the device off.
  2. Hold Volume-Up + Power (varies by model) to reach the recovery menu.
  3. Volume keys to select "Wipe data/factory reset"; Power to confirm.
  4. Choose "Reboot system now".
  5. ${c_yellow}FRP:${c_reset} first boot will require the Google account previously on
     the device. Recover it at https://accounts.google.com/signin/recovery
     if needed. There is no supported bypass.

Before reselling: remove the Google/Samsung account FIRST, then reset, so the
next owner is not blocked by Factory Reset Protection.
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
[[ $# -eq 0 ]] && print_help

case "$1" in
  -h|--help)      print_help ;;
  status)         shift; cmd_status "$@" ;;
  backup)         shift; cmd_backup "${1:-}" ;;
  pull-media)     shift; cmd_pull_media "${1:-}" ;;
  find)           shift; cmd_find ;;
  reset-guide)    shift; cmd_reset_guide ;;
  install-tools)  shift; install_tools ;;
  *) die "Unknown command: $1 (use --help)" ;;
esac
