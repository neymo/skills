---
name: windows-11-hardening
description: >-
  Use when hardening or securing a Windows 11 installation, applying a security
  baseline, enabling Microsoft Defender / firewall / SmartScreen, turning on ASR
  rules, controlled folder access, LSA protection or Credential Guard, disabling
  SMBv1 / LLMNR / NetBIOS, tightening UAC, enabling audit logging, or reducing
  telemetry. Ships an idempotent, reversible PowerShell script.
---

# Windows 11 Hardening

Apply a defensive, CIS-aligned security baseline to a Windows 11 machine using
the bundled [`Invoke-Windows11Hardening.ps1`](Invoke-Windows11Hardening.ps1)
script. Everything is **local and defensive** — no third-party software, no data
exfiltration, no offensive tooling.

## Golden Path

```powershell
# 1. Open PowerShell as Administrator (Win + X -> "Terminal (Admin)")

# 2. Allow the script to run for this session only
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# 3. PREVIEW every change first — nothing is applied
.\Invoke-Windows11Hardening.ps1 -WhatIf

# 4. Apply the safe default baseline
.\Invoke-Windows11Hardening.ps1

# 5. Reboot so LSA protection, Credential Guard, and mitigations take effect
Restart-Computer
```

**Always run `-WhatIf` first** and skim the output. Then apply.

## What It Does

The script is grouped into categories. The **default baseline** applies the
first 16 (including `BackdoorScan`, which is read-only); `HighImpact` is opt-in.

| Category | Hardening applied |
|---|---|
| `Defender` | Real-time/behavior/cloud protection, PUA, network protection, block-at-first-sight, high cloud block level, 15 Attack Surface Reduction (ASR) rules (LSASS theft, Office child processes, USB, ransomware, etc.); **updates definitions now**, then schedules a daily quick scan + weekly full scan, catch-up scans, 8-hour signature interval, 50% CPU cap, and 30-day quarantine retention |
| `Firewall` | Enables Domain/Public/Private profiles, default-deny inbound, block logging |
| `SmartScreen` | App + Edge SmartScreen set to block |
| `UAC` | Consent prompt on secure desktop, admin approval mode, installer detection |
| `Updates` | Enables automatic Windows Update and the `wuauserv` service |
| `Network` | Disables SMBv1, requires SMB signing, disables LLMNR, NetBIOS-over-TCP, and mDNS name-resolution poisoning vectors |
| `Credentials` | LSA protection (RunAsPPL), no LM hash, NTLMv2-only, WDigest cleartext off, restrict anonymous, Credential Guard config |
| `PowerShellLog` | Script-block logging, module logging, transcription |
| `AutoRun` | Disables AutoRun/AutoPlay on all drives |
| `RemoteAccess` | Disables Remote Assistance; if RDP is on, enforces NLA + high encryption (does not silently disable RDP) |
| `Audit` | Enables key logon/account/process-creation audit subcategories + command line in 4688 events |
| `Privacy` | Diagnostic data to Required, disables advertising ID, consumer features, location, Wi-Fi Sense |
| `Hijacking` | DLL search-order hardening (SafeDllSearchMode, block DLL loads from CWD/WebDAV), PrintNightmare driver-install lockdown, disables AutoLogon, enforces Ctrl+Alt+Del, hides last user, disables the Remote Registry service |
| `PhoneTethering` | Disables Mobile Hotspot / Wi-Fi internet sharing, Internet Connection Sharing (ICS) service + UI, network bridging, and auto-connect to suggested open hotspots |
| `BackdoorScan` | **Read-only detection — makes no changes.** Scans for common persistence/backdoor markers: sticky-keys/accessibility IFEO "debugger" backdoors, any IFEO debuggers, Winlogon Shell/Userinit tampering, Run/RunOnce autostarts, rogue scheduled tasks (encoded PowerShell, mshta, LOLBins), services running from Temp/AppData/Public, WMI event-subscription persistence, local admin membership, hosts-file entries, and Startup-folder items. Writes `backdoor-scan-report.txt` and flags suspicious findings. |
| `ScheduledTasks` | Registers recurring maintenance tasks (run as SYSTEM) under Task Scheduler folder `\Windows11-Hardening\`: daily Defender signature update, weekly Defender full scan, and a weekly read-only `BackdoorScan` (re-runs this script). Idempotent (`-Force`). |
| `HighImpact` | **Opt-in.** Controlled Folder Access (ransomware) + Exploit Protection system mitigations (DEP/ASLR/SEHOP). Can break some apps — review first. |

## Common Invocations

```powershell
# Everything, including high-impact items
.\Invoke-Windows11Hardening.ps1 -Category All

# Only specific areas
.\Invoke-Windows11Hardening.ps1 -Category Defender,Firewall,Network

# Custom backup/log location
.\Invoke-Windows11Hardening.ps1 -BackupPath D:\hardening-logs

# Preview a specific category
.\Invoke-Windows11Hardening.ps1 -Category HighImpact -WhatIf

# Just run the read-only backdoor/persistence scan (changes nothing)
.\Invoke-Windows11Hardening.ps1 -Category BackdoorScan
```

`BackdoorScan` reports **indicators**, not proof of compromise — many entries
(e.g. legitimate Run keys or admin accounts) are normal. Review the items marked
`[Suspicious]` and the full report at `<BackupPath>\backdoor-scan-report.txt`.

## Safety & Rollback

The script is built to be safe to run and to undo:

- **`-WhatIf`** shows every change without applying anything.
- **Idempotent** — only writes settings that differ; safe to re-run.
- **System Restore point** created before changes (`Pre-Windows11-Hardening`).
  Skip with `-SkipRestorePoint`.
- **Registry backups** — every changed key is exported as a `.reg` file, plus a
  full `transcript.log`, under
  `C:\Windows11-Hardening-Backup\<timestamp>\` (or your `-BackupPath`).

**To roll back:** run System Restore and pick the `Pre-Windows11-Hardening`
point, or double-click the exported `.reg` files to restore prior values, or
re-run with different `-Category` selections.

## Prerequisites & Notes

- **Run as Administrator.** The script refuses to run otherwise.
- **Reboot after applying** — LSA protection, Credential Guard, and Exploit
  Protection mitigations only activate after a restart.
- **Credential Guard** additionally requires virtualization-based security
  (UEFI, Secure Boot, VBS). The script writes the config; Windows enables it on
  capable hardware after reboot.
- **BitLocker is intentionally not enabled** by this script — full-disk
  encryption needs the recovery key backed up safely first. Enable it manually:
  `Enable-BitLocker -MountPoint C: -RecoveryKeyPath <path> -RecoveryKeyProtector`
  and store the recovery key somewhere safe (e.g. your Microsoft account).
- **Managed devices:** on domain-joined / Intune-managed machines, Group Policy
  or MDM may override these settings. Coordinate with IT before running.
- Tested against Windows 11 22H2 / 23H2 / 24H2.

## Manual Follow-Ups the Script Doesn't Automate

- Enable **BitLocker** and back up the recovery key.
- Confirm **Secure Boot** and **TPM 2.0** are on in UEFI.
- Use a **standard (non-admin) account** for daily use.
- Turn on **Windows Hello** / a strong PIN and enable **Find My Device**.
- Keep **all applications** (browsers, etc.) updated, not just Windows.
- Review installed apps and startup entries; remove what you don't need.
