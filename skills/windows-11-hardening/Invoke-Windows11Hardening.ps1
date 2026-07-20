#Requires -Version 5.1
<#
.SYNOPSIS
    Applies a defensive security-hardening baseline to a Windows 11 installation.

.DESCRIPTION
    Invoke-Windows11Hardening applies a curated set of Microsoft-recommended and
    CIS-aligned security settings to Windows 11. Settings are grouped into
    categories so you can apply everything or just the areas you care about.

    The script is:
      * Idempotent   - safe to run repeatedly; it only changes what is needed.
      * Reversible    - creates a System Restore point and exports changed
                        registry keys to a backup folder before writing.
      * Transparent   - -WhatIf shows every change without applying it, and a
                        full transcript is written to the backup folder.

    It DOES NOT install third-party software, exfiltrate data, or contact the
    network except for Windows' own update/telemetry endpoints you already trust.

.PARAMETER Category
    One or more categories to apply. Defaults to the "safe" baseline set.
    Use -Category All to apply everything (including HighImpact items).

    Available categories:
      Defender        Microsoft Defender AV: real-time, cloud, PUA, network
                      protection, and Attack Surface Reduction (ASR) rules.
      Firewall        Enables all firewall profiles, default-deny inbound.
      SmartScreen     Enables SmartScreen for apps and Edge.
      UAC             Raises User Account Control to a secure prompt level.
      Updates         Enables automatic Windows Update.
      Network         Disables SMBv1, LLMNR, NetBIOS-over-TCP poisoning vectors.
      Credentials     Enables LSA protection (RunAsPPL) and NTLM hardening.
      PowerShellLog   Enables script-block logging, module logging, transcription.
      AutoRun         Disables AutoRun/AutoPlay for all drives.
      RemoteAccess    Disables Remote Assistance; requires NLA if RDP is on.
      Audit           Enables key security audit policies.
      Privacy         Reduces diagnostic-data/telemetry and advertising ID.
      HighImpact      Ransomware Controlled Folder Access + Exploit Protection
                      system mitigations. Can break some apps - review first.

.PARAMETER BackupPath
    Folder for the restore point log, registry backups, and transcript.
    Defaults to C:\Windows11-Hardening-Backup\<timestamp>.

.PARAMETER SkipRestorePoint
    Do not attempt to create a System Restore point (faster, less safe).

.EXAMPLE
    .\Invoke-Windows11Hardening.ps1 -WhatIf
    Preview every change the default baseline would make. Nothing is applied.

.EXAMPLE
    .\Invoke-Windows11Hardening.ps1
    Apply the default safe baseline.

.EXAMPLE
    .\Invoke-Windows11Hardening.ps1 -Category All
    Apply the full baseline including high-impact mitigations.

.EXAMPLE
    .\Invoke-Windows11Hardening.ps1 -Category Defender,Firewall,Network
    Apply only the selected categories.

.NOTES
    Run from an elevated (Administrator) PowerShell session.
    Reboot after running so all settings (LSA protection, mitigations) take effect.
    Tested against Windows 11 22H2/23H2/24H2. Review before use in managed/domain
    environments where Group Policy or Intune may override these settings.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Defender', 'Firewall', 'SmartScreen', 'UAC', 'Updates', 'Network',
        'Credentials', 'PowerShellLog', 'AutoRun', 'RemoteAccess', 'Audit', 'Privacy',
        'HighImpact', 'All')]
    [string[]]$Category = @('Defender', 'Firewall', 'SmartScreen', 'UAC', 'Updates',
        'Network', 'Credentials', 'PowerShellLog', 'AutoRun', 'RemoteAccess', 'Audit',
        'Privacy'),

    [string]$BackupPath = (Join-Path $env:SystemDrive ("Windows11-Hardening-Backup\{0:yyyyMMdd-HHmmss}" -f (Get-Date))),

    [switch]$SkipRestorePoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# All colored console output is centralized here. Write-Host is the right tool
# for an interactive, human-facing CLI, so the analyzer rule is suppressed once.
function Write-Console {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive hardening CLI requires colored console output.')]
    param([string]$Message, [System.ConsoleColor]$Color = [System.ConsoleColor]::White)
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step { param([string]$Message) Write-Console "  -> $Message" Cyan }
function Write-Info { param([string]$Message) Write-Console "[*] $Message" White }
function Write-Good { param([string]$Message) Write-Console "[+] $Message" Green }
function Write-Warn2 { param([string]$Message) Write-Console "[!] $Message" Yellow }

function Backup-RegistryKey {
    param([string]$Path)
    # $Path is a PowerShell registry path, e.g. HKLM:\SOFTWARE\...
    if (-not (Test-Path $Path)) { return }
    $regExe = 'reg.exe'
    $native = $Path -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU' -replace '^HK\\', 'HKLM\'
    $safe = ($native -replace '[\\:]', '_')
    $out = Join-Path $BackupPath "reg_$safe.reg"
    try {
        & $regExe export $native $out /y *> $null
    }
    catch {
        Write-Warn2 "Could not back up $native ($($_.Exception.Message))"
    }
}

function Set-RegValue {
    <#
        Idempotent registry setter. Creates the key if missing, backs the key up
        once before the first change, and only writes when the value differs.
        Honors -WhatIf via ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type = 'DWord'
    )

    $current = $null
    if (Test-Path $Path) {
        try { $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $current = $null }
    }

    if ($null -ne $current -and "$current" -eq "$Value") {
        Write-Verbose "Already set: $Path\$Name = $Value"
        return
    }

    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set to '$Value' ($Type)")) {
        Backup-RegistryKey -Path $Path
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Step "$Path\$Name = $Value"
    }
}

function Invoke-Native {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($PSCmdlet.ShouldProcess($Description, 'Execute')) {
        try {
            & $Action
            Write-Step $Description
        }
        catch {
            Write-Warn2 "$Description failed: $($_.Exception.Message)"
        }
    }
}

function Test-Selected {
    param([string]$Name)
    return ($Category -contains 'All') -or ($Category -contains $Name)
}

# ---------------------------------------------------------------------------
# Category implementations
# ---------------------------------------------------------------------------

function Set-DefenderHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Microsoft Defender Antivirus'
    if (-not (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        Write-Warn2 'Defender cmdlets unavailable (third-party AV installed?). Skipping.'
        return
    }

    Invoke-Native 'Enable real-time monitoring' { Set-MpPreference -DisableRealtimeMonitoring $false }
    Invoke-Native 'Enable behavior monitoring' { Set-MpPreference -DisableBehaviorMonitoring $false }
    Invoke-Native 'Enable script scanning' { Set-MpPreference -DisableScriptScanning $false }
    Invoke-Native 'Enable IOAV (downloaded file) protection' { Set-MpPreference -DisableIOAVProtection $false }
    Invoke-Native 'Cloud-delivered protection: High' { Set-MpPreference -MAPSReporting Advanced }
    Invoke-Native 'Automatic sample submission: safe samples' { Set-MpPreference -SubmitSamplesConsent SendSafeSamples }
    Invoke-Native 'Block at first sight' { Set-MpPreference -DisableBlockAtFirstSeen $false }
    Invoke-Native 'PUA protection: Enabled' { Set-MpPreference -PUAProtection Enabled }
    Invoke-Native 'Cloud block level: High' { Set-MpPreference -CloudBlockLevel High }
    Invoke-Native 'Cloud extended timeout: 50s' { Set-MpPreference -CloudExtendedTimeout 50 }
    Invoke-Native 'Enable Network Protection (block)' { Set-MpPreference -EnableNetworkProtection Enabled }

    # Attack Surface Reduction (ASR) rules - GUID => Enabled(1)
    $asr = @{
        'BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550' = 'Block executable content from email/webmail'
        'D4F940AB-401B-4EFC-AADC-AD5F3C50688A' = 'Block Office apps creating child processes'
        '3B576869-A4EC-4529-8536-B80A7769E899' = 'Block Office apps creating executable content'
        '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84' = 'Block Office apps injecting into other processes'
        'D3E037E1-3EB8-44C8-A917-57927947596D' = 'Block JS/VBS launching downloaded executables'
        '5BEB7EFE-FD9A-4556-801D-275E5FFC04CC' = 'Block obfuscated scripts'
        '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B' = 'Block Win32 API calls from Office macros'
        '01443614-CD74-433A-B99E-2ECDC07BFC25' = 'Block untrusted/unsigned executables from USB'
        'C1DB55AB-C21A-4637-BB3F-A12568109D35' = 'Use advanced ransomware protection'
        '9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2' = 'Block credential stealing from LSASS'
        'D1E49AAC-8F56-4280-B9BA-993A6D77406C' = 'Block process creations from PSExec/WMI'
        'B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4' = 'Block untrusted/unsigned processes on USB'
        '26190899-1602-49E8-8B27-EB1D0A1CE869' = 'Block Office comms apps creating child processes'
        '7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C' = 'Block Adobe Reader creating child processes'
        'E6DB77E5-3DF2-4CF1-B95A-636979351E5B' = 'Block persistence through WMI event subscription'
    }
    foreach ($guid in $asr.Keys) {
        Invoke-Native "ASR: $($asr[$guid])" {
            Add-MpPreference -AttackSurfaceReductionRules_Ids $guid -AttackSurfaceReductionRules_Actions Enabled
        }.GetNewClosure()
    }
}

function Set-FirewallHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Windows Defender Firewall'
    if (-not (Get-Command Set-NetFirewallProfile -ErrorAction SilentlyContinue)) {
        Write-Warn2 'Firewall cmdlets unavailable. Skipping.'
        return
    }
    Invoke-Native 'Enable all firewall profiles, default-deny inbound' {
        Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True `
            -DefaultInboundAction Block -DefaultOutboundAction Allow `
            -NotifyOnListen True -LogBlocked True -LogAllowed False `
            -LogMaxSizeKilobytes 16384
    }
}

function Set-SmartScreenHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'SmartScreen'
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableSmartScreen' -Value 1
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'ShellSmartScreenLevel' -Value 'Block' -Type String
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'SmartScreenEnabled' -Value 1
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'SmartScreenPuaEnabled' -Value 1
}

function Set-UACHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'User Account Control (UAC)'
    $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-RegValue -Path $p -Name 'EnableLUA' -Value 1
    Set-RegValue -Path $p -Name 'ConsentPromptBehaviorAdmin' -Value 2   # prompt for consent on secure desktop
    Set-RegValue -Path $p -Name 'ConsentPromptBehaviorUser' -Value 3    # prompt standard users for credentials
    Set-RegValue -Path $p -Name 'PromptOnSecureDesktop' -Value 1
    Set-RegValue -Path $p -Name 'EnableInstallerDetection' -Value 1
    Set-RegValue -Path $p -Name 'FilterAdministratorToken' -Value 1     # admin approval mode for built-in admin
}

function Set-UpdatesHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Windows Update'
    $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    Set-RegValue -Path $p -Name 'NoAutoUpdate' -Value 0
    Set-RegValue -Path $p -Name 'AUOptions' -Value 4                    # auto download and schedule install
    Invoke-Native 'Ensure Windows Update service (wuauserv) is enabled' {
        Set-Service -Name wuauserv -StartupType Automatic
    }
}

function Set-NetworkHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Network attack surface'
    Invoke-Native 'Disable SMBv1 client/server' {
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        if (Get-Command Disable-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Invoke-Native 'Require SMB signing (server + client)' {
        Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
        Set-SmbClientConfiguration -RequireSecuritySignature $true -Force
    }
    # Disable LLMNR (multicast name resolution poisoning)
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Value 0
    # Disable NetBIOS over TCP/IP for all interfaces
    Invoke-Native 'Disable NetBIOS over TCP/IP on all interfaces' {
        $root = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            New-ItemProperty -Path $_.PSPath -Name 'NetbiosOptions' -Value 2 -PropertyType DWord -Force | Out-Null
        }
    }
    # Disable mDNS
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name 'EnableMDNS' -Value 0
}

function Set-CredentialHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Credential and authentication hardening'
    # LSA protection (RunAsPPL) - protects LSASS from credential dumping
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RunAsPPL' -Value 1
    # Do not store LM hash
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'NoLMHash' -Value 1
    # Restrict anonymous enumeration of SAM accounts and shares
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymous' -Value 1
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymousSAM' -Value 1
    # NTLM: send NTLMv2 only, refuse LM & NTLM
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -Value 5
    # Disable WDigest cleartext credential caching
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Value 0
    # Enable Credential Guard config (takes effect with VBS + reboot)
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -Value 1
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'RequirePlatformSecurityFeatures' -Value 1
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\LSA' -Name 'LsaCfgFlags' -Value 1
}

function Set-PowerShellLogging {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'PowerShell logging'
    $sb = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
    Set-RegValue -Path $sb -Name 'EnableScriptBlockLogging' -Value 1
    $mod = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
    Set-RegValue -Path $mod -Name 'EnableModuleLogging' -Value 1
    Set-RegValue -Path "$mod\ModuleNames" -Name '*' -Value '*' -Type String
    $tr = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription'
    Set-RegValue -Path $tr -Name 'EnableTranscripting' -Value 1
    Set-RegValue -Path $tr -Name 'EnableInvocationHeader' -Value 1
}

function Set-AutoRunHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'AutoRun / AutoPlay'
    Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveTypeAutoRun' -Value 255
    Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoAutorun' -Value 1
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoAutoplayfornonVolume' -Value 1
}

function Set-RemoteAccessHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Remote access'
    # Disable Remote Assistance
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name 'fAllowToGetHelp' -Value 0
    # If RDP is enabled, require Network Level Authentication and encryption.
    $rdpDenied = $null
    try { $rdpDenied = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction Stop).fDenyTSConnections } catch { Write-Verbose 'RDP state key not present.' }
    if ($rdpDenied -eq 0) {
        Write-Warn2 'RDP is enabled - enforcing NLA and high encryption (not disabling it).'
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -Value 2
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'MinEncryptionLevel' -Value 3
    }
    else {
        Write-Step 'RDP is disabled - leaving it disabled.'
    }
}

function Set-AuditHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Security audit policy'
    $subs = @(
        'Logon', 'Logoff', 'Account Lockout', 'Special Logon',
        'Process Creation', 'Security Group Management', 'User Account Management',
        'Audit Policy Change', 'Authentication Policy Change',
        'Credential Validation', 'Other Object Access Events'
    )
    foreach ($s in $subs) {
        Invoke-Native "Audit '$s' (success+failure)" {
            & auditpol.exe /set /subcategory:"$s" /success:enable /failure:enable | Out-Null
        }.GetNewClosure()
    }
    # Include command line in process-creation events (4688)
    Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1
}

function Set-PrivacyHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'Telemetry / privacy'
    # Diagnostic data: Required only (0 = Security is Enterprise-only; 1 = Required)
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 1
    # Disable advertising ID
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' -Name 'DisabledByGroupPolicy' -Value 1
    # Disable Consumer Experiences (suggested apps/ads)
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1
    # Disable location for the device
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableLocation' -Value 1
    # Disable Wi-Fi Sense
    Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' -Name 'value' -Value 0
}

function Set-HighImpactHardening {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Info 'HIGH-IMPACT mitigations (review carefully)'
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        Invoke-Native 'Controlled Folder Access (ransomware protection): Enabled' {
            Set-MpPreference -EnableControlledFolderAccess Enabled
        }
    }
    if (Get-Command Set-ProcessMitigation -ErrorAction SilentlyContinue) {
        Invoke-Native 'Exploit Protection: enable DEP, ASLR (BottomUp+ForceRelocate), SEHOP system-wide' {
            Set-ProcessMitigation -System -Enable DEP, EmulateAtlThunks, BottomUp, HighEntropy, SEHOP, TerminateOnError
        }
    }
    # SEHOP
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'DisableExceptionChainValidation' -Value 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Console ''
Write-Console '================================================================' DarkCyan
Write-Console '   Windows 11 Security Hardening' DarkCyan
Write-Console '================================================================' DarkCyan
Write-Console ''

if (-not (Test-Admin)) {
    throw 'This script must be run from an elevated (Administrator) PowerShell session.'
}

$os = (Get-CimInstance Win32_OperatingSystem).Caption
Write-Info "Detected OS: $os"
if ($os -notmatch 'Windows 1[01]|Windows Server') {
    Write-Warn2 "This script targets Windows 11. Detected '$os'. Proceed with caution."
}

if (-not (Test-Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}
Write-Info "Backup / log folder: $BackupPath"

$transcript = Join-Path $BackupPath 'transcript.log'
try { Start-Transcript -Path $transcript -Force | Out-Null } catch { Write-Warn2 "Could not start transcript: $($_.Exception.Message)" }

if (-not $SkipRestorePoint -and -not $WhatIfPreference) {
    Write-Info 'Creating System Restore point...'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Pre-Windows11-Hardening' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Good 'Restore point created.'
    }
    catch {
        Write-Warn2 "Restore point not created: $($_.Exception.Message)"
        Write-Warn2 'Registry keys are still backed up to the backup folder as .reg files.'
    }
}

Write-Console ''
Write-Info ("Categories selected: {0}" -f ($Category -join ', '))
if ($WhatIfPreference) { Write-Warn2 'WHATIF MODE - no changes will be applied.' }
Write-Console ''

$map = [ordered]@{
    Defender      = ${function:Set-DefenderHardening}
    Firewall      = ${function:Set-FirewallHardening}
    SmartScreen   = ${function:Set-SmartScreenHardening}
    UAC           = ${function:Set-UACHardening}
    Updates       = ${function:Set-UpdatesHardening}
    Network       = ${function:Set-NetworkHardening}
    Credentials   = ${function:Set-CredentialHardening}
    PowerShellLog = ${function:Set-PowerShellLogging}
    AutoRun       = ${function:Set-AutoRunHardening}
    RemoteAccess  = ${function:Set-RemoteAccessHardening}
    Audit         = ${function:Set-AuditHardening}
    Privacy       = ${function:Set-PrivacyHardening}
    HighImpact    = ${function:Set-HighImpactHardening}
}

foreach ($name in $map.Keys) {
    if (Test-Selected -Name $name) {
        try {
            & $map[$name]
        }
        catch {
            Write-Warn2 "Category '$name' encountered an error: $($_.Exception.Message)"
        }
        Write-Console ''
    }
}

Write-Console '================================================================' DarkCyan
Write-Good 'Hardening pass complete.'
Write-Warn2 'REBOOT REQUIRED for LSA protection, Credential Guard, and mitigations to take effect.'
Write-Info "Backups and transcript saved to: $BackupPath"
Write-Console '================================================================' DarkCyan

try { Stop-Transcript | Out-Null } catch { Write-Verbose 'No active transcript to stop.' }
