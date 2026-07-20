---
name: android-hardening
description: >-
  Use when hardening or securing an Android phone, tablet, or emulator, applying
  a security baseline over ADB, recovering a device that may be hacked/
  compromised, turning on Google Play Protect, blocking installs from unknown
  sources, setting encrypted Private DNS, hiding lock-screen notifications,
  auditing sideloaded apps / device admins / accessibility services, or scanning
  for backdoor and spyware indicators. Ships an idempotent, reversible Bash
  script driven by adb.
---

# Android Hardening

Apply a defensive security baseline to an Android device and audit it for signs
of compromise using the bundled [`harden-android.sh`](harden-android.sh) script.
Everything is **local and defensive** — it talks only to the device you connect
over USB/ADB. No third-party software, no network calls, no data exfiltration,
no offensive tooling.

This is built for the "my phone got hacked" case: run the read-only **Audit**
and **BackdoorScan** first to see what looks wrong, then apply the hardening
categories to close the common attack vectors. It complements — it does not
replace — a factory reset plus credential rotation from a trusted device.

## Golden Path

```bash
# 1. On the phone: enable Developer Options, then turn on USB debugging.
#    Connect it by USB and accept the RSA authorization prompt.

# 2. Confirm the computer can see the device.
adb devices

# 3. READ-ONLY first: inventory the device and scan for compromise markers.
./harden-android.sh --category Audit,BackdoorScan

# 4. PREVIEW every change the baseline would make — nothing is applied.
./harden-android.sh --dry-run

# 5. Apply the safe default baseline.
./harden-android.sh
```

**Always run `--dry-run` first** and skim the output. Then apply.

## What It Does

The script is grouped into categories. The **default baseline** runs the first
six plus the read-only `BackdoorScan`; `HighImpact` and `DisableAdb` are opt-in.

| Category | What it does |
|---|---|
| `Audit` | **Read-only.** Inventory: model, Android version + security patch level, third-party (user-installed) apps and their install source, active device admins, enabled accessibility services, notification listeners, and the state of key security toggles (Play Protect, unknown sources, ADB, Private DNS, lock-screen notifications). Writes a report. |
| `PlayProtect` | Enables Google Play Protect / package verification, verification of ADB-installed apps, and suspicious-app upload. |
| `UnknownSources` | Disables the legacy "install from unknown sources" toggle and revokes the per-app **install unknown apps** permission (`REQUEST_INSTALL_PACKAGES`) from every third-party app. |
| `Lockscreen` | Hides private notification content on the lock screen and stops passwords being revealed as you type. |
| `Network` | Turns off always-on Wi-Fi/Bluetooth scanning, disables the "join open network" prompt, avoids bad Wi-Fi, and sets an encrypted **Private DNS** resolver (DNS-over-TLS, `dns.google` by default — override with `--private-dns`). |
| `Privacy` | Opts out of ad tracking / personalization and usage-and-diagnostics reporting. |
| `BackdoorScan` | **Read-only detection — makes no changes.** Flags common compromise markers: third-party **accessibility services** and **device admins** (top spyware persistence vectors), third-party **notification listeners** (can read OTPs), apps that can **draw overlays**, apps that can **install other apps**, apps holding **SMS/call-log** permissions, and **sideloaded** apps. Writes a report and marks findings `[SUSPICIOUS]`. |
| `HighImpact` | **Opt-in.** Aggressive changes that break convenience features: turns **Bluetooth + NFC off** and revokes the **draw-over-other-apps** (overlay) permission from every third-party app. Review first. |
| `DisableAdb` | **Opt-in, runs last.** Turns off USB debugging and hides Developer Options. This **disconnects the script from the device**, so it is never in the default baseline. |

## Common Invocations

```bash
# Just the read-only audit / scan (change nothing)
./harden-android.sh --category Audit
./harden-android.sh --category BackdoorScan

# Everything, including high-impact items and disabling ADB last
./harden-android.sh --category All

# Only specific areas
./harden-android.sh --category PlayProtect,UnknownSources,Network

# Target a specific device when several are attached
./harden-android.sh -s <serial>

# Use Cloudflare's resolver for Private DNS, custom backup location
./harden-android.sh --private-dns one.one.one.one --backup-path ~/android-hardening

# List categories
./harden-android.sh --list-categories
```

`BackdoorScan` reports **indicators**, not proof of compromise — many entries
(e.g. a legitimate password manager holding accessibility access) are normal.
Review the items marked `[SUSPICIOUS]` and the full `report-<timestamp>.txt`.

## Safety & Rollback

The script is built to be safe to run and to undo:

- **`--dry-run`** shows every change without applying anything.
- **Idempotent** — only writes settings that differ; safe to re-run.
- **Reversible** — before the first change it writes a runnable
  `restore-<timestamp>.sh` that puts every changed setting and app-op back to
  its prior value, alongside the report, under
  `~/android-hardening-backup/<timestamp>/` (or your `--backup-path`).

**To roll back:** run `bash ~/android-hardening-backup/<timestamp>/restore-<timestamp>.sh`.

## Prerequisites & Notes

- **`adb` (Android platform-tools)** must be on your PATH.
- **USB debugging** must be enabled on the device and this computer authorized
  (accept the on-device RSA prompt). The script refuses to run without a ready,
  authorized device, and requires `-s <serial>` when several are attached.
- Works against a physical device over USB or a running **emulator/AVD**.
- Settings are applied via the `shell` user's `WRITE_SECURE_SETTINGS` /
  app-ops permissions — **no root required** — but that also means some OEM skins
  may expose extra toggles this script can't reach. On managed (MDM/Android
  Enterprise) devices, policy may override these settings; coordinate with IT.

## Manual Follow-Ups the Script Can't Automate

Over plain ADB the script deliberately does **not** set your PIN, remove
accounts, or wipe the device. After running it:

- Set a strong **screen-lock** PIN/passphrase + biometrics.
- **Update** Android and all apps.
- From a **trusted device**, change passwords + enable **2FA** on Google/Apple,
  email, and banking; review recovery options and active sessions.
- Call your **carrier** to check for SIM-swap / unauthorized changes.
- **Remove** apps flagged by `BackdoorScan` that you don't recognize — revoke
  their device-admin / accessibility access first, then uninstall.
- If compromise is confirmed, **factory reset** and restore only trusted data:
  Settings > System > Reset options > Erase all data.
