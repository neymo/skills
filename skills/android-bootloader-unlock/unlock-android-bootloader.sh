#!/usr/bin/env bash
#
# unlock-android-bootloader.sh
# ---------------------------------------------------------------------------
# Interactively unlock (or re-lock) the bootloader of an Android device you own,
# via fastboot, for development (flashing GSIs, custom recoveries/ROMs, kernels).
#
# IMPORTANT — scope & ethics:
#   * This is an OFFICIAL, manufacturer-supported developer feature.
#   * It requires physical possession, the device signed-in and unlocked, and
#     the user-enabled "OEM unlocking" toggle in Developer Options.
#   * It does NOT and cannot bypass a lock screen, PIN/pattern, Google account
#     (Factory Reset Protection / FRP), or carrier lock.
#   * Unlocking ERASES ALL USER DATA and may void the warranty / trip
#     verified-boot (Knox) flags.
#
# Usage:
#   chmod +x unlock-android-bootloader.sh
#   ./unlock-android-bootloader.sh --dry-run     # print the plan, change nothing
#   ./unlock-android-bootloader.sh               # interactive unlock
#   ./unlock-android-bootloader.sh --method oem  # force `fastboot oem unlock`
#   ./unlock-android-bootloader.sh --method flashing
#   ./unlock-android-bootloader.sh --critical    # also `flashing unlock_critical`
#   ./unlock-android-bootloader.sh --relock      # re-lock the bootloader
#   ./unlock-android-bootloader.sh --install-tools
#   ./unlock-android-bootloader.sh --help
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
METHOD="auto"        # auto | flashing | oem
DO_CRITICAL=0
DO_RELOCK=0
DRY_RUN=0
ASSUME_YES=0
INSTALL_ONLY=0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_green=$'\033[1;32m'
c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'
log()  { printf '%s==>%s %s\n' "$c_blue"   "$c_reset" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$c_green"  "$c_reset" "$*"; }
warn() { printf '%s[!!]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[xx]%s %s\n' "$c_red"    "$c_reset" "$*" >&2; exit 1; }

# Run a command, or just print it in --dry-run mode.
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '   %s(dry-run)%s %s\n' "$c_yellow" "$c_reset" "$*"
  else
    "$@"
  fi
}

print_help() {
  awk 'NR==1 {next} /^#/ {sub(/^#[[:space:]]?/, ""); print; next} {exit}' "$0"
  exit 0
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method)        METHOD="${2:?--method needs a value (auto|flashing|oem)}"; shift ;;
    --critical)      DO_CRITICAL=1 ;;
    --relock)        DO_RELOCK=1 ;;
    --dry-run)       DRY_RUN=1 ;;
    -y|--yes)        ASSUME_YES=1 ;;
    --install-tools) INSTALL_ONLY=1 ;;
    -h|--help)       print_help ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
  shift
done

case "$METHOD" in auto|flashing|oem) ;; *) die "Invalid --method '$METHOD'";; esac

# ---------------------------------------------------------------------------
# Tooling
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

install_tools() {
  log "Installing Android platform-tools (adb + fastboot)"
  if have apt-get; then
    local sudo=""; [[ $EUID -ne 0 ]] && sudo="sudo"
    run $sudo apt-get update -y
    run $sudo apt-get install -y android-tools-adb android-tools-fastboot
  elif have brew; then
    run brew install --cask android-platform-tools
  else
    warn "No apt/brew found. Install the official platform-tools manually:"
    echo "     https://developer.android.com/tools/releases/platform-tools"
    echo "     (download the zip, extract, and add it to your PATH)"
    return 1
  fi
}

ensure_tools() {
  if have adb && have fastboot; then
    ok "adb + fastboot found"
    return 0
  fi
  warn "adb/fastboot not found."
  if [[ $DRY_RUN -eq 1 ]]; then
    warn "(dry-run) would offer to install android platform-tools"
    return 0
  fi
  if confirm "Install Android platform-tools now?"; then
    install_tools || die "Could not install platform-tools automatically."
    if ! { have adb && have fastboot; }; then
      die "platform-tools still not on PATH."
    fi
  else
    die "adb + fastboot are required. Re-run with --install-tools or install manually."
  fi
}

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------
confirm() {
  # confirm "question?"  -> returns 0 on yes
  [[ $ASSUME_YES -eq 1 ]] && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

confirm_destructive() {
  # Require typing an exact phrase; not satisfied by --yes.
  local phrase="$1" reply
  warn "This ERASES ALL DATA on the device and cannot be undone."
  read -r -p "Type '$phrase' to proceed: " reply
  [[ "$reply" == "$phrase" ]]
}

# ---------------------------------------------------------------------------
# Device detection
# ---------------------------------------------------------------------------
BRAND=""; MODEL=""; ANDROID=""

adb_one_device() {
  local n
  n=$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
  [[ "$n" == "1" ]]
}

read_device_info() {
  BRAND=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r' || true)
  MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)
  ANDROID=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' || true)
  log "Device: ${BRAND:-?} ${MODEL:-?} (Android ${ANDROID:-?})"
}

vendor_token_note() {
  # Brands that require a code/token obtained from a vendor portal.
  local b; b=$(printf '%s' "$BRAND" | tr '[:upper:]' '[:lower:]')
  case "$b" in
    xiaomi|redmi|poco)
      warn "Xiaomi/Redmi/POCO require the Mi Unlock tool + account bind (7-30 day wait):"
      echo "     https://en.miui.com/unlock/" ;;
    motorola|moto)
      warn "Motorola requires an unlock code from its portal (uses get_identifier_token):"
      echo "     https://motorola-global-portal.custhelp.com/app/standalone/bootloader/unlock-your-device-a" ;;
    sony)
      warn "Sony Xperia requires an unlock code from the Open Devices portal:"
      echo "     https://developer.sony.com/develop/open-devices/get-started/unlock-bootloader" ;;
    oneplus)
      warn "Some OnePlus models need an unlock token from support; many accept 'fastboot oem unlock' directly." ;;
    htc)
      warn "HTC requires a token from HTCdev: https://www.htcdev.com/bootloader" ;;
    samsung)
      die "Samsung devices do not use fastboot. Enable OEM unlocking, then boot into Download mode and long-press Volume-Up. This script cannot automate Odin/Download-mode unlock." ;;
    huawei|honor)
      die "Huawei/Honor stopped issuing bootloader unlock codes; there is no supported unlock path." ;;
    *) : ;;
  esac
}

# ---------------------------------------------------------------------------
# Fastboot helpers
# ---------------------------------------------------------------------------
wait_for_fastboot() {
  log "Waiting for the device in fastboot/bootloader mode..."
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '   %s(dry-run)%s would wait for: fastboot devices\n' "$c_yellow" "$c_reset"
    return 0
  fi
  local _
  for _ in $(seq 1 30); do
    if fastboot devices 2>/dev/null | grep -q .; then
      ok "Device detected by fastboot"
      return 0
    fi
    sleep 1
  done
  die "No device seen by fastboot. Check drivers/cable (see SKILL.md Troubleshooting)."
}

do_unlock() {
  local m="$METHOD"
  if [[ "$m" == "auto" ]]; then
    # Prefer the modern command; fall back to oem if it is unknown.
    m="flashing"
  fi

  if [[ "$m" == "flashing" ]]; then
    log "Unlocking: fastboot flashing unlock"
    run fastboot flashing unlock || {
      warn "'flashing unlock' failed; retrying with legacy 'oem unlock'"
      run fastboot oem unlock
    }
    if [[ $DO_CRITICAL -eq 1 ]]; then
      log "Unlocking critical partitions: fastboot flashing unlock_critical"
      run fastboot flashing unlock_critical || warn "unlock_critical not supported / not needed"
    fi
  else
    log "Unlocking: fastboot oem unlock"
    run fastboot oem unlock
  fi
  warn "Now CONFIRM on the device screen (Volume keys to select, Power to accept)."
}

do_relock() {
  local m="$METHOD"; [[ "$m" == "auto" ]] && m="flashing"
  if [[ "$m" == "flashing" ]]; then
    log "Re-locking: fastboot flashing lock"
    run fastboot flashing lock || run fastboot oem lock
  else
    log "Re-locking: fastboot oem lock"
    run fastboot oem lock
  fi
  warn "Confirm on the device screen. Re-locking also WIPES the device."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local action="unlock"; [[ $DO_RELOCK -eq 1 ]] && action="re-lock"
  cat <<EOF
${c_yellow}Android bootloader ${action} helper${c_reset}
This tool is for a device YOU OWN. It does NOT bypass lock screens, PINs,
patterns, or Factory Reset Protection. Unlocking ERASES ALL DATA.

EOF

  if [[ $INSTALL_ONLY -eq 1 ]]; then
    install_tools
    exit 0
  fi

  ensure_tools

  # In dry-run we still show the plan even without a device attached.
  if [[ $DRY_RUN -eq 0 ]]; then
    adb devices >/dev/null 2>&1 || true
    adb_one_device || die "Connect exactly one authorized device (check 'adb devices' and accept the USB prompt)."
    read_device_info
    vendor_token_note
  else
    log "(dry-run) skipping live device detection"
    echo
    log "Plan:"
    echo "   1. adb devices                 # confirm one authorized device"
    echo "   2. read brand/model/android    # vendor-specific guidance"
    echo "   3. adb reboot bootloader       # enter fastboot"
    echo "   4. fastboot devices            # confirm fastboot connection"
    if [[ $DO_RELOCK -eq 1 ]]; then
      echo "   5. fastboot flashing lock      # (or 'oem lock')  -- WIPES DEVICE"
    else
      echo "   5. fastboot flashing unlock    # (or 'oem unlock') -- WIPES DEVICE"
      [[ $DO_CRITICAL -eq 1 ]] && echo "      fastboot flashing unlock_critical"
    fi
    echo "   6. confirm on-device prompt, then: fastboot reboot"
    echo
    ok "Dry run complete — nothing was changed."
    exit 0
  fi

  echo
  if [[ $DO_RELOCK -eq 1 ]]; then
    confirm_destructive "RELOCK AND WIPE" || die "Aborted."
  else
    warn "Before continuing: back up anything you need. Unlocking wipes the device."
    confirm "Ready to reboot into the bootloader and unlock?" || die "Aborted."
    confirm_destructive "UNLOCK AND WIPE" || die "Aborted."
  fi

  log "Rebooting device into bootloader..."
  run adb reboot bootloader
  wait_for_fastboot

  if [[ $DO_RELOCK -eq 1 ]]; then
    do_relock
  else
    do_unlock
  fi

  log "Rebooting device..."
  run fastboot reboot
  ok "Done. First boot will factory-reset and may take several minutes."
}

main "$@"
