---
name: android-device-recovery
description: >-
  Use when regaining access to an Android device you OWN through supported,
  non-bypass means — locating/ringing/erasing it with Find My Device, doing a
  factory reset from stock recovery, recovering a forgotten Google/Samsung
  account or password, retrieving data via ADB backup when the device is still
  authorized, or preparing a device for safe resale. Does NOT bypass lock
  screens, PIN/pattern, or Factory Reset Protection (FRP).
---

# Android Device Recovery (supported, non-bypass)

Regain access to, reset, or recover data from **your own** Android device using
only manufacturer-supported paths. Ships a helper,
[`android-recovery.sh`](android-recovery.sh), for the ADB-based steps.

> **Scope.** Everything here keeps the device's security model intact. It does
> **not** bypass a lock screen, PIN, pattern, password, or Factory Reset
> Protection (FRP). If you can't prove ownership (know the Google/Samsung
> account credentials that were on the device), these steps intentionally will
> not grant access — that protection is working as designed.

## Decision guide

| Situation | Supported path |
|---|---|
| Device lost/stolen, want to locate/ring/lock/erase | **Find My Device** (remote) |
| Forgot screen lock, device signed into a Google account | Reset via **account** / factory reset, then re-sign-in |
| Forgot the Google account password itself | **Google Account Recovery** |
| Forgot Samsung screen lock | **Samsung Find / Remote unlock** (if enabled) |
| Device boots & USB debugging already authorized | **ADB backup / pull** your data before reset |
| Selling/returning the device | Sign out of accounts → factory reset (clears FRP correctly) |
| Device stuck/bootlooping | **Factory reset from stock recovery** |

## Remote: Find My Device

For a phone that's online and tied to your Google account:

1. Go to <https://www.google.com/android/find> (or the Find My Device app on
   another device) and sign in with **the account that's on the phone**.
2. Choose **Play sound**, **Secure device** (lock + message), or **Erase
   device**. Erase is irreversible and removes the device from the account.

Samsung equivalent (if SmartThings Find / Samsung account was set up):
<https://smartthingsfind.samsung.com>.

## Recover the Google account / password

If the blocker is the account password (not the screen lock):
<https://accounts.google.com/signin/recovery>. Use a known recovery email/phone
or a previously-used password. This preserves FRP — after recovery you can sign
in on the device normally.

## Factory reset from stock recovery

Use when the device won't boot normally or you've forgotten the lock **but know
the Google account** that will be requested after reset (FRP).

```text
1. Power off the device.
2. Hold Volume-Up + Power (varies by model) until the recovery menu appears.
3. Volume keys to highlight "Wipe data/factory reset", Power to select.
4. Confirm, then "Reboot system now".
5. On first boot you MUST sign in with the Google account previously on the
   device (Factory Reset Protection). No account = no access, by design.
```

> Before reselling: **remove the account first** (Settings > Accounts > remove
> Google account, and Settings > Security > find "Factory reset protection")
> so the new owner isn't blocked by FRP.

## ADB data recovery (device still authorized)

If the device boots and you previously enabled USB debugging + authorized this
computer, you can pull data before resetting. The bundled script wraps this:

```bash
chmod +x android-recovery.sh

./android-recovery.sh status                 # show device + auth state
./android-recovery.sh backup ./out           # adb backup apps+data to ./out
./android-recovery.sh pull-media ./out        # copy DCIM/Pictures/Download/Movies
./android-recovery.sh find                    # open Find My Device in a browser
./android-recovery.sh reset-guide             # print the stock-recovery steps
./android-recovery.sh --help
```

`android-recovery.sh` never attempts to defeat authentication: `backup`/`pull`
only work if the device screen is unlocked and the RSA key is already
authorized. If it isn't, the script tells you to unlock/authorize on the device.

## Troubleshooting

- **`adb` shows `unauthorized`** — unlock the phone and tap **Allow** on the
  "Allow USB debugging?" prompt. If it never appears, revoke authorizations in
  Developer options and reconnect.
- **`adb` shows `no devices`** — enable USB debugging, use a data-capable cable,
  and (Linux) add a udev rule / `plugdev` membership; WSL2 needs `usbipd`.
- **Stuck on FRP after reset** — this is expected; sign in with the previous
  Google account, or recover that account first. There is no supported bypass.
- **`adb backup` is deprecated / empty on newer Android** — many apps opt out of
  backup; prefer `pull-media` and app-specific cloud exports.
