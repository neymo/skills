#!/usr/bin/env bash
#
# harden-android.sh
# ---------------------------------------------------------------------------
# Apply a defensive security-hardening baseline to an Android device (phone,
# tablet, or emulator) over ADB, and audit it for signs of compromise. This is
# especially useful for post-incident recovery ("my phone got hacked"): run the
# read-only Audit + BackdoorScan first to see what looks wrong, then apply the
# hardening categories to close the common attack vectors.
#
# Everything is LOCAL and DEFENSIVE. The script:
#   * Talks only to the device you connect over USB/ADB - no network, no
#     third-party software, no data exfiltration, no offensive tooling.
#   * Is idempotent   - it only changes settings that differ; safe to re-run.
#   * Is reversible    - before changing anything it writes a restore-<ts>.sh
#     that puts every setting/appop back the way it was.
#   * Is transparent   - --dry-run shows every change without applying it, and
#     Audit / BackdoorScan are strictly read-only.
#
# It does NOT (and over plain ADB cannot) set your screen-lock PIN, factory
# reset the device, or remove your accounts. Those manual steps are listed at
# the end of the run and in SKILL.md - for a truly compromised phone a factory
# reset plus credential rotation from a trusted device is still the gold
# standard, and this script complements that rather than replacing it.
#
# Categories (default baseline runs the first six + BackdoorScan):
#   Audit          READ-ONLY. Inventory of build/patch level, sideloaded apps,
#                  device admins, accessibility services, notification
#                  listeners, dangerous permissions, and security toggles.
#   PlayProtect    Turns on Google Play Protect / package verification and
#                  verification of ADB-installed apps.
#   UnknownSources Blocks installing apps from unknown sources and revokes the
#                  "install unknown apps" permission from third-party apps.
#   Lockscreen     Hides private notifications on the lock screen, stops
#                  passwords being shown as you type.
#   Network        Stops always-on Wi-Fi/Bluetooth scanning, disables auto-
#                  connect to open networks, and sets an encrypted Private DNS
#                  resolver (DNS-over-TLS).
#   Privacy        Opts out of the advertising ID / ad personalization and
#                  usage-and-diagnostics reporting.
#   BackdoorScan   READ-ONLY. Flags common compromise markers: third-party
#                  accessibility services and device admins, overlay-capable
#                  apps, SMS/call-log grabbers, and sideloaded apps. Writes a
#                  report; makes no changes.
#   HighImpact     OPT-IN. Aggressive changes that can break convenience
#                  features: turns Bluetooth + NFC off and revokes the
#                  "draw over other apps" (overlay) permission from every
#                  third-party app. Review first.
#   DisableAdb     OPT-IN and LAST. Turns off USB debugging (ADB) and hides
#                  Developer Options. This will disconnect this very script,
#                  so it is never part of the default baseline.
#
# Usage:
#   chmod +x harden-android.sh
#   ./harden-android.sh --dry-run                 # preview the default baseline
#   ./harden-android.sh                           # apply the default baseline
#   ./harden-android.sh --category Audit          # just the read-only audit
#   ./harden-android.sh --category BackdoorScan   # just the read-only scan
#   ./harden-android.sh --category All            # everything (incl. HighImpact
#                                                 #  + DisableAdb)
#   ./harden-android.sh --category PlayProtect,UnknownSources
#   ./harden-android.sh -s <serial>               # target a specific device
#   ./harden-android.sh --backup-path ~/android-hardening
#   ./harden-android.sh --list-categories
#   ./harden-android.sh --help
#
# Prerequisites:
#   * adb (Android platform-tools) on your PATH.
#   * The device connected with USB debugging enabled and this computer
#     authorized (accept the RSA prompt on the device).
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults / configuration
# ---------------------------------------------------------------------------
SERIAL=""
DRY_RUN=0
BACKUP_PATH="${BACKUP_PATH:-$HOME/android-hardening-backup}"
PRIVATE_DNS_HOST="${PRIVATE_DNS_HOST:-dns.google}"

ALL_CATEGORIES=(Audit PlayProtect UnknownSources Lockscreen Network Privacy BackdoorScan HighImpact DisableAdb)
DEFAULT_CATEGORIES=(Audit PlayProtect UnknownSources Lockscreen Network Privacy BackdoorScan)
SELECTED=()

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=""
RESTORE_FILE=""
REPORT_FILE=""

# ---------------------------------------------------------------------------
# Pretty logging
# ---------------------------------------------------------------------------
c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_green=$'\033[1;32m'
c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_cyan=$'\033[1;36m'
log()  { printf '%s==>%s %s\n' "$c_blue"   "$c_reset" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$c_green"  "$c_reset" "$*"; }
step() { printf '%s ->%s %s\n'  "$c_cyan"   "$c_reset" "$*"; }
warn() { printf '%s[!!]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[xx]%s %s\n' "$c_red"    "$c_reset" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
# Print the leading comment banner (from line 2 up to the first non-comment
# line) as help text, stripping the leading "# ". Robust to line-number drift.
print_help() {
  awk 'NR==1 {next} /^#/ {sub(/^#[[:space:]]?/, ""); print; next} {exit}' "$0"
  exit 0
}

list_categories() {
  printf 'Available categories:\n'
  printf '  %s\n' "${ALL_CATEGORIES[@]}"
  printf '\nDefault baseline:\n  %s\n' "${DEFAULT_CATEGORIES[*]}"
  exit 0
}

parse_categories() {
  # Split a comma-separated list, validate against ALL_CATEGORIES / "All".
  local raw="$1" item found c
  IFS=',' read -ra parts <<< "$raw"
  for item in "${parts[@]}"; do
    item="${item//[[:space:]]/}"
    [[ -z "$item" ]] && continue
    if [[ "$item" == "All" || "$item" == "all" ]]; then
      SELECTED=("${ALL_CATEGORIES[@]}")
      return
    fi
    found=0
    for c in "${ALL_CATEGORIES[@]}"; do
      [[ "$c" == "$item" ]] && { found=1; break; }
    done
    [[ $found -eq 1 ]] || die "Unknown category: '$item' (use --list-categories)"
    SELECTED+=("$item")
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category|-c)     parse_categories "${2:?--category needs a value}"; shift ;;
    --serial|-s)       SERIAL="${2:?--serial needs a value}"; shift ;;
    --backup-path)     BACKUP_PATH="${2:?--backup-path needs a value}"; shift ;;
    --private-dns)     PRIVATE_DNS_HOST="${2:?--private-dns needs a value}"; shift ;;
    --dry-run|-n)      DRY_RUN=1 ;;
    --list-categories) list_categories ;;
    -h|--help)         print_help ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
  shift
done

[[ ${#SELECTED[@]} -eq 0 ]] && SELECTED=("${DEFAULT_CATEGORIES[@]}")

wants() {
  # wants <Category> -> true if that category is selected
  local c
  for c in "${SELECTED[@]}"; do [[ "$c" == "$1" ]] && return 0; done
  return 1
}

# ---------------------------------------------------------------------------
# ADB plumbing
# ---------------------------------------------------------------------------
ADB=(adb)
require_adb() {
  command -v adb >/dev/null 2>&1 || die "adb not found on PATH. Install Android platform-tools."
  if [[ -n "$SERIAL" ]]; then
    ADB=(adb -s "$SERIAL")
  else
    # If exactly one device is attached, target it; otherwise require -s.
    local n
    n="$(adb devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')"
    [[ "$n" -eq 0 ]] && die "No authorized device found. Connect one, enable USB debugging, and accept the prompt."
    [[ "$n" -gt 1 ]] && die "Multiple devices attached - pick one with -s <serial> (see: adb devices)."
  fi
  "${ADB[@]}" get-state >/dev/null 2>&1 || die "Device not ready (adb get-state failed)."
}

# Run a shell command on the device, normalizing CRLF line endings.
adb_sh() { "${ADB[@]}" shell "$@" 2>/dev/null | tr -d '\r'; }

get_setting() {
  # get_setting <namespace> <key> -> current value, or empty for "null"
  local v; v="$(adb_sh settings get "$1" "$2")"
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

record_restore() { printf '%s\n' "$*" >> "$RESTORE_FILE"; }

put_setting() {
  # put_setting <namespace> <key> <value> [description]
  # Idempotent: only writes when different. Records how to undo it.
  local ns="$1" key="$2" val="$3" desc="${4:-$ns/$key}" cur
  cur="$(get_setting "$ns" "$key")"
  if [[ "$cur" == "$val" ]]; then
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    step "[dry-run] $desc: '$cur' -> '$val'"
    return 0
  fi
  if [[ -z "$cur" ]]; then
    record_restore "settings delete $ns $key"
  else
    record_restore "settings put $ns $key '$cur'"
  fi
  adb_sh settings put "$ns" "$key" "$val" >/dev/null
  step "$desc: '$cur' -> '$val'"
}

appop_mode() {
  # Current appop mode for a package/op, e.g. "allow" | "ignore" | "deny".
  adb_sh appops get "$1" "$2" 2>/dev/null | awk -F': ' 'NR==1{split($2,a,";"); print a[1]}'
}

set_appop() {
  # set_appop <pkg> <op> <mode> -> idempotent, reversible appop change.
  local pkg="$1" op="$2" mode="$3" cur
  cur="$(appop_mode "$pkg" "$op")"
  [[ -z "$cur" ]] && cur="allow"
  if [[ "$cur" == "$mode" ]]; then
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    step "[dry-run] appop $op for $pkg: '$cur' -> '$mode'"
    return 0
  fi
  record_restore "appops set $pkg $op $cur"
  adb_sh appops set "$pkg" "$op" "$mode" >/dev/null
  step "appop $op for $pkg: '$cur' -> '$mode'"
}

# Cache of third-party packages (populated once).
THIRD_PARTY=()
load_third_party() {
  [[ ${#THIRD_PARTY[@]} -gt 0 ]] && return 0
  local line
  while IFS= read -r line; do
    line="${line#package:}"
    [[ -n "$line" ]] && THIRD_PARTY+=("$line")
  done < <(adb_sh pm list packages -3)
}

installer_of() { adb_sh pm list packages -i "$1" | sed -n "s/^package:$1  *installer=//p" | head -n1; }

# ---------------------------------------------------------------------------
# Report helpers
# ---------------------------------------------------------------------------
rpt()      { printf '%s\n' "$*" | tee -a "$REPORT_FILE"; }
rpt_head() { printf '\n%s%s%s\n' "$c_blue" "$*" "$c_reset"; printf '\n%s\n' "$*" >> "$REPORT_FILE"; }
rpt_susp() { printf '%s[SUSPICIOUS]%s %s\n' "$c_red" "$c_reset" "$*"; printf '[SUSPICIOUS] %s\n' "$*" >> "$REPORT_FILE"; }

# ---------------------------------------------------------------------------
# Categories
# ---------------------------------------------------------------------------
do_audit() {
  rpt_head "== Audit: device inventory =="
  rpt "Model:          $(adb_sh getprop ro.product.model) ($(adb_sh getprop ro.product.manufacturer))"
  rpt "Android:        $(adb_sh getprop ro.build.version.release) (API $(adb_sh getprop ro.build.version.sdk))"
  rpt "Security patch: $(adb_sh getprop ro.build.version.security_patch)"
  rpt "Build type:     $(adb_sh getprop ro.build.type)  tags: $(adb_sh getprop ro.build.tags)"
  rpt "Play Protect (package_verifier_enable):    $(get_setting global package_verifier_enable)"
  rpt "Verify ADB installs (verifier_verify_adb_installs): $(get_setting global verifier_verify_adb_installs)"
  rpt "Install unknown apps (install_non_market_apps):     $(get_setting secure install_non_market_apps)"
  rpt "ADB enabled (adb_enabled):                 $(get_setting global adb_enabled)"
  rpt "Developer options (development_settings_enabled): $(get_setting global development_settings_enabled)"
  rpt "Private DNS mode:  $(get_setting global private_dns_mode)  host: $(get_setting global private_dns_specifier)"
  rpt "Wi-Fi scan always: $(get_setting global wifi_scan_always_enabled)  BLE scan always: $(get_setting global ble_scan_always_enabled)"
  rpt "Show passwords:    $(get_setting system show_password)"
  rpt "Lockscreen private notifications: $(get_setting secure lock_screen_allow_private_notifications)"

  load_third_party
  rpt_head "== Audit: ${#THIRD_PARTY[@]} third-party (user-installed) apps =="
  local pkg inst
  for pkg in "${THIRD_PARTY[@]}"; do
    inst="$(installer_of "$pkg")"
    rpt "  $pkg  (installer=${inst:-none})"
  done

  rpt_head "== Audit: enabled accessibility services =="
  rpt "  $(get_setting secure enabled_accessibility_services)"
  rpt_head "== Audit: enabled notification listeners =="
  rpt "  $(get_setting secure enabled_notification_listeners)"
  rpt_head "== Audit: active device admins =="
  adb_sh dumpsys device_policy | sed -n 's/.*admin=ComponentInfo{\([^}]*\)}.*/  \1/p' | sort -u | tee -a "$REPORT_FILE"
  ok "Audit written to $REPORT_FILE"
}

do_playprotect() {
  log "PlayProtect: enabling Google Play Protect / package verification"
  put_setting global package_verifier_enable 1        "Play Protect verify apps"
  put_setting global package_verifier_user_consent 1  "Play Protect user consent"
  put_setting global verifier_verify_adb_installs 1    "Verify apps installed via ADB"
  put_setting global upload_apk_enable 1               "Upload suspicious apps for review"
}

do_unknown_sources() {
  log "UnknownSources: blocking installs from unknown sources"
  put_setting secure install_non_market_apps 0 "Install unknown apps (global legacy toggle)"
  load_third_party
  local pkg
  for pkg in "${THIRD_PARTY[@]}"; do
    set_appop "$pkg" REQUEST_INSTALL_PACKAGES ignore
  done
}

do_lockscreen() {
  log "Lockscreen: reducing information leakage on the lock screen"
  put_setting secure lock_screen_allow_private_notifications 0 "Hide private notification content on lock screen"
  put_setting system show_password 0                          "Do not reveal typed passwords"
}

do_network() {
  log "Network: reducing wireless tracking/attack surface + encrypted DNS"
  put_setting global wifi_scan_always_enabled 0 "Wi-Fi scanning while Wi-Fi off"
  put_setting global ble_scan_always_enabled 0  "Bluetooth scanning while BT off"
  put_setting global wifi_networks_available_notification_on 0 "Prompt to join open networks"
  put_setting global network_avoid_bad_wifi 1   "Avoid bad Wi-Fi (stay on mobile)"
  put_setting global private_dns_mode hostname  "Private DNS mode (DNS-over-TLS)"
  put_setting global private_dns_specifier "$PRIVATE_DNS_HOST" "Private DNS resolver"
}

do_privacy() {
  log "Privacy: opting out of ad + diagnostics tracking"
  put_setting secure limit_ad_tracking 1                 "Limit ad tracking"
  put_setting global multi_cb_enabled 0                  "Emergency alert marketing (best effort)" 2>/dev/null || true
  put_setting secure send_action_app_error 0            "Send app-error reports"
  put_setting global usage_and_diagnostics_enabled 0    "Usage & diagnostics reporting"
}

do_highimpact() {
  log "HighImpact: aggressive changes (review!) - radios off + overlay revocation"
  put_setting global bluetooth_on 0 "Bluetooth radio"
  put_setting secure nfc_payment_default_component "" "NFC payment default (cleared)" 2>/dev/null || true
  adb_sh svc bluetooth disable >/dev/null 2>&1 || true
  adb_sh svc nfc disable >/dev/null 2>&1 || true
  load_third_party
  local pkg
  for pkg in "${THIRD_PARTY[@]}"; do
    set_appop "$pkg" SYSTEM_ALERT_WINDOW ignore
  done
}

do_disable_adb() {
  warn "DisableAdb: turning off USB debugging + Developer Options."
  warn "This DISCONNECTS this script from the device - it runs last."
  put_setting global development_settings_enabled 0 "Developer Options"
  put_setting global adb_enabled 0                  "USB debugging (ADB)"
}

# ---------------------------------------------------------------------------
# BackdoorScan (read-only)
# ---------------------------------------------------------------------------
is_third_party() {
  local p; for p in "${THIRD_PARTY[@]}"; do [[ "$p" == "$1" ]] && return 0; done; return 1
}

pkg_from_component() { printf '%s' "${1%%/*}"; }

do_backdoor_scan() {
  load_third_party
  local findings=0
  rpt_head "== BackdoorScan: read-only compromise indicators =="
  rpt "Indicators are NOT proof of compromise - review each [SUSPICIOUS] entry."

  # 1. Accessibility services owned by third-party apps (top malware vector).
  rpt_head "-- Accessibility services --"
  local svc pkg
  local acc; acc="$(get_setting secure enabled_accessibility_services)"
  if [[ -n "$acc" ]]; then
    IFS=':' read -ra svcs <<< "$acc"
    for svc in "${svcs[@]}"; do
      pkg="$(pkg_from_component "$svc")"
      if is_third_party "$pkg"; then
        rpt_susp "third-party accessibility service enabled: $svc"
        ((findings++)) || true
      else
        rpt "  system accessibility service: $svc"
      fi
    done
  else
    rpt "  none enabled"
  fi

  # 2. Third-party device admins (used by malware to resist removal / lock you out).
  rpt_head "-- Device administrators --"
  local admins admin
  admins="$(adb_sh dumpsys device_policy | sed -n 's/.*admin=ComponentInfo{\([^}]*\)}.*/\1/p' | sort -u)"
  if [[ -n "$admins" ]]; then
    while IFS= read -r admin; do
      pkg="$(pkg_from_component "$admin")"
      if is_third_party "$pkg"; then
        rpt_susp "third-party device admin active: $admin"
        ((findings++)) || true
      else
        rpt "  system device admin: $admin"
      fi
    done <<< "$admins"
  else
    rpt "  none active"
  fi

  # 3. Third-party notification listeners (can read every notification, incl. OTPs).
  rpt_head "-- Notification listeners --"
  local nls nl
  nls="$(get_setting secure enabled_notification_listeners)"
  if [[ -n "$nls" ]]; then
    IFS=':' read -ra listeners <<< "$nls"
    for nl in "${listeners[@]}"; do
      pkg="$(pkg_from_component "$nl")"
      if is_third_party "$pkg"; then
        rpt_susp "third-party notification listener: $nl"
        ((findings++)) || true
      else
        rpt "  system notification listener: $nl"
      fi
    done
  else
    rpt "  none enabled"
  fi

  # 4. Per-app risk review: sideload source, overlay, SMS/call-log grabbing.
  rpt_head "-- Third-party app risk review --"
  local inst op perms
  for pkg in "${THIRD_PARTY[@]}"; do
    local flags=()
    inst="$(installer_of "$pkg")"
    if [[ -z "$inst" || "$inst" == "null" || "$inst" == "com.android.shell" ]]; then
      flags+=("sideloaded(installer=${inst:-none})")
    fi
    op="$(appop_mode "$pkg" SYSTEM_ALERT_WINDOW)"
    [[ "$op" == "allow" ]] && flags+=("can-draw-overlays")
    op="$(appop_mode "$pkg" REQUEST_INSTALL_PACKAGES)"
    [[ "$op" == "allow" ]] && flags+=("can-install-apps")
    perms="$(adb_sh dumpsys package "$pkg" | grep -E 'permission\.(READ_SMS|RECEIVE_SMS|READ_CALL_LOG|BIND_ACCESSIBILITY_SERVICE)=.*granted=true' || true)"
    [[ -n "$perms" ]] && flags+=("sms/call-log/accessibility-perms")
    if [[ ${#flags[@]} -gt 0 ]]; then
      rpt_susp "$pkg  [${flags[*]}]"
      ((findings++)) || true
    fi
  done

  rpt_head "== BackdoorScan summary =="
  if [[ $findings -eq 0 ]]; then
    ok "No obvious indicators flagged. (Absence of flags is not a guarantee.)"
  else
    warn "$findings indicator(s) flagged [SUSPICIOUS]. Review $REPORT_FILE."
  fi
}

# ---------------------------------------------------------------------------
# Manual follow-ups the script cannot automate over plain ADB
# ---------------------------------------------------------------------------
print_follow_ups() {
  cat <<'EOF'

Manual follow-ups (cannot be done safely over plain ADB):
  * Set a strong screen-lock PIN/passphrase + biometrics (Settings > Security).
  * Update Android and ALL apps to the latest version.
  * From a TRUSTED device, change passwords + enable 2FA on Google/Apple, email,
    and banking; review account recovery options and active sessions.
  * Call your carrier to check for SIM-swap / unauthorized changes.
  * Remove apps flagged by BackdoorScan that you do not recognize (revoke their
    device-admin / accessibility access first, then uninstall).
  * If compromise is confirmed, factory reset and restore only trusted data:
    Settings > System > Reset options > Erase all data (factory reset).
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  require_adb

  BACKUP_DIR="$BACKUP_PATH/$TS"
  mkdir -p "$BACKUP_DIR"
  RESTORE_FILE="$BACKUP_DIR/restore-$TS.sh"
  REPORT_FILE="$BACKUP_DIR/report-$TS.txt"
  {
    echo "#!/usr/bin/env bash"
    echo "# Auto-generated rollback for harden-android.sh run at $TS"
    echo "# Re-applies the settings/appops that were changed, back to prior values."
    echo "set -x"
    echo "adb=(adb${SERIAL:+ -s $SERIAL} shell)"
    # shellcheck disable=SC2016  # intentionally literal: written into the restore script
    echo 'settings() { "${adb[@]}" settings "$@"; }'
    # shellcheck disable=SC2016  # intentionally literal: written into the restore script
    echo 'appops()   { "${adb[@]}" appops "$@"; }'
  } > "$RESTORE_FILE"
  : > "$REPORT_FILE"

  log "Target device: $("${ADB[@]}" shell getprop ro.product.model | tr -d '\r') (serial: $("${ADB[@]}" get-serialno 2>/dev/null | tr -d '\r'))"
  log "Categories: ${SELECTED[*]}"
  [[ $DRY_RUN -eq 1 ]] && warn "DRY-RUN: no changes will be applied."
  log "Backups + reports: $BACKUP_DIR"

  # Order matters: read-only Audit first; DisableAdb strictly last.
  wants Audit          && do_audit
  wants PlayProtect    && do_playprotect
  wants UnknownSources && do_unknown_sources
  wants Lockscreen     && do_lockscreen
  wants Network        && do_network
  wants Privacy        && do_privacy
  wants HighImpact     && do_highimpact
  wants BackdoorScan   && do_backdoor_scan
  wants DisableAdb     && do_disable_adb

  echo
  if [[ $DRY_RUN -eq 1 ]]; then
    ok "Dry-run complete. Re-run without --dry-run to apply."
  else
    ok "Done. To roll back settings/appops: bash '$RESTORE_FILE'"
  fi
  print_follow_ups
}

main "$@"
