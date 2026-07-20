---
name: android-bootloader-unlock
description: >-
  Use when unlocking (or re-locking) the bootloader of an Android device you own
  via fastboot for development — enabling OEM unlocking, entering fastboot mode,
  running `fastboot flashing unlock` / `fastboot oem unlock`, obtaining a
  vendor unlock code/token (Xiaomi, Motorola, Sony, OnePlus, HTC), or flashing
  custom images/recoveries. Ships an interactive, safety-gated shell script.
  NOT for bypassing lock screens, PIN/pattern, or Factory Reset Protection (FRP).
---

# Android Bootloader Unlock (fastboot)

Unlock the bootloader of **your own** Android device so you can flash custom
images (GSIs, custom recoveries/ROMs, kernels) using the bundled
[`unlock-android-bootloader.sh`](unlock-android-bootloader.sh) script.

> **Scope / ethics.** Bootloader unlocking is an official, manufacturer-supported
> developer feature. It requires physical possession, the device to be signed in
> and unlocked, and the user-enabled **OEM unlocking** toggle in Developer
> Options. This skill does **not** and cannot bypass a lock screen, PIN/pattern,
> Google account (FRP), or carrier lock. Unlocking **erases all user data** and
> may void the warranty and trip Knox/verified-boot flags.

## Golden Path

```bash
chmod +x unlock-android-bootloader.sh

# 0. Preview the exact steps/commands for your device — changes nothing
./unlock-android-bootloader.sh --dry-run

# 1. On the phone: Settings > About phone > tap "Build number" 7x to enable
#    Developer options. Then Settings > System > Developer options:
#      - turn on "USB debugging"
#      - turn on "OEM unlocking"   (greyed out? see Troubleshooting)

# 2. Plug in via USB, authorize the RSA prompt, then run:
./unlock-android-bootloader.sh
```

The script walks you through the whole flow interactively, with explicit typed
confirmation before the destructive step.

## What the script does

1. **Tooling check** — verifies `adb` and `fastboot` (Android platform-tools).
   Offers to install them (`apt`, `brew`, or the official zip) if missing.
2. **Device check** — `adb devices`, confirms exactly one authorized device,
   and reads brand/model/Android version.
3. **Pre-flight** — reminds you to back up (unlock wipes the device) and verifies
   the **OEM unlocking** state where readable.
4. **Enter fastboot** — `adb reboot bootloader`, then waits for `fastboot devices`.
5. **Unlock** — picks the right command for the device generation:
   - Modern (2015+ / Pixel, most brands): `fastboot flashing unlock`
     (and optionally `fastboot flashing unlock_critical`).
   - Legacy: `fastboot oem unlock`.
   - **Vendor-token brands** (Xiaomi, Motorola, Sony, OnePlus, HTC): prints the
     brand-specific portal steps + the `fastboot oem get_identifier_token` /
     `fastboot oem unlock <CODE>` sequence, since these need a code from the
     vendor.
   Then confirm the on-device prompt with volume/power keys.
6. **Finish** — `fastboot reboot`. First boot after unlock takes several minutes
   and factory-resets the device.

## Common invocations

```bash
./unlock-android-bootloader.sh --dry-run            # print the plan, do nothing
./unlock-android-bootloader.sh                       # interactive unlock
./unlock-android-bootloader.sh --method oem          # force `fastboot oem unlock`
./unlock-android-bootloader.sh --method flashing     # force `fastboot flashing unlock`
./unlock-android-bootloader.sh --critical            # also unlock_critical
./unlock-android-bootloader.sh --relock              # re-lock the bootloader
./unlock-android-bootloader.sh --install-tools       # just install platform-tools
./unlock-android-bootloader.sh --help
```

## Vendor unlock portals (token/code required)

| Brand | Where to get the unlock code/permission |
|---|---|
| Xiaomi / Redmi / POCO | Mi Unlock tool + account bind (7–30 day waiting period): https://en.miui.com/unlock/ |
| Motorola | https://motorola-global-portal.custhelp.com/app/standalone/bootloader/unlock-your-device-a |
| Sony Xperia | https://developer.sony.com/develop/open-devices/get-started/unlock-bootloader |
| OnePlus | Request unlock token via support (older models: `fastboot oem unlock` directly) |
| HTC | https://www.htcdev.com/bootloader |
| Google Pixel / Nexus | No code — just `fastboot flashing unlock` (enable OEM unlocking first) |
| Samsung | No fastboot — uses Download/Odin mode; enable OEM unlocking, then long-press Vol-Up in Download mode |

## Troubleshooting

- **"OEM unlocking" is greyed out** — connect to the internet and sign in so the
  device can check unlock eligibility; remove any work profile/MDM; on some
  carrier models it is permanently disabled. Let the device sit online a while.
- **`fastboot devices` shows nothing** — install the fastboot USB driver
  (Windows), try a different cable/port (data-capable), or `sudo` / add a udev
  rule on Linux (`plugdev` group). WSL2 needs USB passthrough via `usbipd`.
- **`FAILED (remote: 'unknown command')`** — try the other `--method`
  (`flashing` vs `oem`).
- **Device won't boot after unlock** — normal on first boot (it factory-resets);
  wait 5–10 minutes.
- **Samsung / Huawei** — not fastboot-based; the script detects these and prints
  the correct path (Download mode for Samsung; Huawei no longer issues codes).

## Re-locking

Re-lock before returning a device to stock: `./unlock-android-bootloader.sh --relock`
runs `fastboot flashing lock` (or `fastboot oem lock`). **This also wipes the
device.** Only re-lock with stock, signed firmware installed, or the device may
fail to boot.
