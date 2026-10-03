<#
.SYNOPSIS
  Prepare a borrowed Windows 10/11 laptop for KKS Explorer's remote tests and measurements, and undo it all afterwards.

.DESCRIPTION
  Run in an elevated PowerShell (Run as administrator):

    powershell -ExecutionPolicy Bypass -File kks-test-host.ps1 -Setup -PublicKey "ssh-ed25519 AAAA… kks-vm-tests"
    powershell -ExecutionPolicy Bypass -File kks-test-host.ps1 -Status
    powershell -ExecutionPolicy Bypass -File kks-test-host.ps1 -Revert

  What -Setup changes (each step recorded in C:\ProgramData\KKS-test\state.json, which -Revert reads):
  - a local STANDARD account "kks" (not an administrator) with a random password. Tests run inside it; a standard
    account cannot open other users' folders, so the owner's files stay out of reach;
  - automatic sign-in to "kks" at boot (UI Automation needs a signed-in, unlocked desktop). The password is kept as
    an LSA secret like Sysinternals Autologon does, not in plain text. Skipped (with a message) if the laptop already
    signs someone in automatically: their stored password is never touched;
  - the OpenSSH server (a Windows optional feature), only if it is not installed yet; the test key may log in as
    "kks" only, by key, from the local network only. If the owner already uses OpenSSH, nothing of theirs changes
    except one added "Match User kks" block (removed by -Revert);
  - PowerShell as OpenSSH's shell (the tests send PowerShell commands), only if no shell was set before;
  - a separate power plan "KKS test" (no sleep, no screen-off, no lock on wake while on the charger), made active;
    the owner's plan is untouched and comes back on -Revert;
  - firewall rules in group "KKS Explorer test": the app's sync ports (8421–8441 TCP) and mDNS (5353 UDP), local
    network only;
  - C:\kks, the tests' working folder (owned by "kks").

  What -Setup never does: read, copy or change anything in other users' profiles; touch BitLocker, Defender,
  Windows Update, the camera's privacy switch, or any other account; install anything besides the OpenSSH feature.

  -Revert undoes each recorded step in reverse order, deletes the "kks" account with its profile and C:\kks, and
  leaves C:\ProgramData\KKS-test\revert.log. Run it before giving the laptop back. Restart afterwards.

.NOTES
  KKS Explorer, decision 0033 (Windows platform) / docs: apps/windows/README.md. Safe to run -Status any time.
#>
param([switch]$Setup, [switch]$Revert, [switch]$Status, [string]$PublicKey = "", [string]$User = "kks")

$ErrorActionPreference = "Stop"
$Dir = "C:\ProgramData\KKS-test"
$StateFile = Join-Path $Dir "state.json"
$Work = "C:\kks"
$Winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$SshConfig = "C:\ProgramData\ssh\sshd_config"
$Marker = "# KKS Explorer test host (kks-test-host.ps1): remove with -Revert"

function Assert-Admin {
  $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this in PowerShell opened with 'Run as administrator'."
  }
}

function Load-State { if (Test-Path $StateFile) { Get-Content $StateFile -Raw | ConvertFrom-Json } else { $null } }
function Save-State($s) { New-Item -ItemType Directory -Force $Dir | Out-Null; $s | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding UTF8 }

# the automatic sign-in password as an LSA secret ("DefaultPassword"), the way Windows' own AutoAdminLogon reads it
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class KksLsa {
  [StructLayout(LayoutKind.Sequential)] struct US { public ushort Length, MaximumLength; public IntPtr Buffer; }
  [StructLayout(LayoutKind.Sequential)] struct OA { public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
  [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system, ref OA attrs, uint access, out IntPtr handle);
  [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr handle, ref US key, IntPtr data);
  [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr handle);
  [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint status);
  static US Str(string s) { var u = new US(); u.Buffer = Marshal.StringToHGlobalUni(s); u.Length = (ushort)(s.Length * 2); u.MaximumLength = (ushort)(u.Length + 2); return u; }
  public static void Store(string key, string secret) {
    var oa = new OA(); IntPtr h;
    uint r = LsaOpenPolicy(IntPtr.Zero, ref oa, 0x00000020, out h);   // POLICY_CREATE_SECRET
    if (r != 0) throw new Exception("LsaOpenPolicy: " + LsaNtStatusToWinError(r));
    var k = Str(key); IntPtr data = IntPtr.Zero;
    if (secret != null) { var d = Str(secret); data = Marshal.AllocHGlobal(Marshal.SizeOf(d)); Marshal.StructureToPtr(d, data, false); }
    r = LsaStorePrivateData(h, ref k, data);                          // null data deletes the secret
    LsaClose(h);
    if (r != 0 && secret != null) throw new Exception("LsaStorePrivateData: " + LsaNtStatusToWinError(r));
  }
}
"@

function RegValue($path, $name) { (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }

function Do-Status {
  $s = Load-State
  "State file: " + $(if ($s) { "$StateFile (set up $($s.created))" } else { "none (nothing set up)" })
  "Account $User`: " + $(if (Get-LocalUser $User -ErrorAction SilentlyContinue) { "present" } else { "absent" })
  "Automatic sign-in: AutoAdminLogon=" + (RegValue $Winlogon "AutoAdminLogon") + " user=" + (RegValue $Winlogon "DefaultUserName")
  $cap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
  "OpenSSH server: " + $cap.State + " / service " + $(try { (Get-Service sshd).Status } catch { "absent" })
  "Active power plan: " + ((powercfg /getactivescheme) -join " ")
  "Firewall rules (KKS Explorer test): " + @(Get-NetFirewallRule -Group "KKS Explorer test" -ErrorAction SilentlyContinue).Count
  "Folder $Work`: " + $(if (Test-Path $Work) { "present" } else { "absent" })
  $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }
  "This laptop's addresses: " + (($ip | ForEach-Object { $_.IPAddress }) -join ", ")
}

function Do-Setup {
  Assert-Admin
  if (-not $PublicKey.StartsWith("ssh-")) { throw "Give the test computer's public key: -PublicKey ""ssh-ed25519 AAAA…""" }
  if (Load-State) { throw "Already set up (see -Status). Run -Revert first if you want to start over." }
  $s = [ordered]@{ created = (Get-Date).ToString("s"); computer = $env:COMPUTERNAME; user = $User; steps = @() }
  Save-State $s
  function Step($name, $data) { $s.steps += [ordered]@{ step = $name; data = $data }; Save-State $s; Write-Host "  done: $name" }

  Write-Host "1. The test account"
  if (Get-LocalUser $User -ErrorAction SilentlyContinue) { throw "A local account named '$User' already exists: not touching it. Nothing was changed." }
  $chars = [char[]]"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#%+-="
  $pw = -join (1..24 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
  $sec = ConvertTo-SecureString $pw -AsPlainText -Force
  New-LocalUser -Name $User -Password $sec -FullName "KKS Explorer tests" -Description "Temporary test account (kks-test-host.ps1)" -PasswordNeverExpires -AccountNeverExpires | Out-Null
  Add-LocalGroupMember -Group (Get-LocalGroup -SID "S-1-5-32-545") -Member $User     # Users (any language)
  $s.user_sid = (Get-LocalUser $User).SID.Value
  Step "user" @{}

  Write-Host "2. The working folder"
  $hadWork = Test-Path $Work
  if (-not $hadWork) { New-Item -ItemType Directory $Work | Out-Null }
  $acl = Get-Acl $Work
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($User, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")))
  Set-Acl $Work $acl
  Step "work" @{ existed = $hadWork }

  Write-Host "3. OpenSSH server"
  $cap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
  $hadSsh = $cap.State -eq "Installed"
  $svcBefore = if ($hadSsh) { (Get-Service sshd).StartType.ToString() } else { "" }
  if (-not $hadSsh) { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
  Start-Service sshd          # writes the default sshd_config on its first start
  Set-Service sshd -StartupType Automatic
  $hadConfig = Test-Path $SshConfig
  Copy-Item $SshConfig (Join-Path $Dir "sshd_config.before")
  $keys = Join-Path $Dir "authorized_keys"
  Set-Content $keys $PublicKey -Encoding ascii
  icacls $keys /inheritance:r /grant "*S-1-5-18:F" /grant "*S-1-5-32-544:F" /grant "${User}:R" | Out-Null
  # appended at the end: Match blocks must come last in sshd_config
  Add-Content $SshConfig ("`r`n$Marker`r`nMatch User $User`r`n    AuthorizedKeysFile __PROGRAMDATA__/KKS-test/authorized_keys`r`n    PasswordAuthentication no`r`n    KbdInteractiveAuthentication no`r`n# end KKS Explorer test host`r`n") -Encoding ascii
  Restart-Service sshd
  $defaultRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
  $ruleScope = if ($defaultRule) { ($defaultRule | Get-NetFirewallAddressFilter).RemoteAddress -join "," } else { "" }
  if (-not $hadSsh -and $defaultRule) { Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -RemoteAddress LocalSubnet }
  if (-not $defaultRule) { New-NetFirewallRule -Name "kks-test-sshd" -Group "KKS Explorer test" -DisplayName "KKS test: OpenSSH (local network)" -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress LocalSubnet -Action Allow | Out-Null }
  Step "ssh" @{ installed_before = $hadSsh; start_type_before = $svcBefore; rule_scope_before = $ruleScope }
  $shellBefore = RegValue "HKLM:\SOFTWARE\OpenSSH" "DefaultShell"
  if (-not $shellBefore) {
    New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null
    Step "shell" @{}
  } else { Write-Host "  OpenSSH already has a shell set ($shellBefore): left as it is. Tests expect PowerShell." }

  Write-Host "4. Power plan"
  $orig = ((powercfg /getactivescheme) -join " ") -replace '.*?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*', '$1'
  $new = ((powercfg /duplicatescheme $orig) -join " ") -replace '.*?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*', '$1'
  powercfg /changename $new "KKS test" "Temporary plan for KKS Explorer tests (kks-test-host.ps1)" | Out-Null
  powercfg /setacvalueindex $new SUB_SLEEP STANDBYIDLE 0 | Out-Null
  powercfg /setacvalueindex $new SUB_SLEEP HIBERNATEIDLE 0 | Out-Null
  powercfg /setacvalueindex $new SUB_VIDEO VIDEOIDLE 0 | Out-Null
  powercfg /setacvalueindex $new SUB_NONE CONSOLELOCK 0 | Out-Null
  powercfg /setactive $new | Out-Null
  Step "power" @{ original = $orig; plan = $new }

  Write-Host "5. Firewall (local network only)"
  New-NetFirewallRule -Name "kks-test-sync" -Group "KKS Explorer test" -DisplayName "KKS test: sync ports" -Direction Inbound -Protocol TCP -LocalPort 8421-8441 -RemoteAddress LocalSubnet -Action Allow | Out-Null
  New-NetFirewallRule -Name "kks-test-mdns" -Group "KKS Explorer test" -DisplayName "KKS test: mDNS" -Direction Inbound -Protocol UDP -LocalPort 5353 -RemoteAddress LocalSubnet -Action Allow | Out-Null
  Step "firewall" @{}

  Write-Host "6. Automatic sign-in to $User"
  if ((RegValue $Winlogon "AutoAdminLogon") -eq "1") {
    Write-Host "  This laptop already signs someone in automatically: not changed (their stored password stays untouched)."
    Write-Host "  Sign in to the '$User' account by hand before the tests (password: see below)."
  } else {
    $before = @{}
    foreach ($n in "AutoAdminLogon", "DefaultUserName", "DefaultDomainName", "AutoLogonCount") { $before[$n] = RegValue $Winlogon $n }
    [KksLsa]::Store("DefaultPassword", $pw)
    Set-ItemProperty $Winlogon AutoAdminLogon "1"
    Set-ItemProperty $Winlogon DefaultUserName $User
    Set-ItemProperty $Winlogon DefaultDomainName $env:COMPUTERNAME
    Remove-ItemProperty $Winlogon AutoLogonCount -ErrorAction SilentlyContinue
    Step "autologon" $before
  }

  Write-Host ""
  Write-Host "Ready. Restart the laptop: it signs in to '$User' by itself. The tests then reach it over SSH:"
  Do-Status | Select-String "addresses"
  Write-Host "The '$User' password (only needed to sign in by hand): $pw"
  Write-Host "Undo everything with: powershell -ExecutionPolicy Bypass -File $PSCommandPath -Revert"
}

function Do-Revert {
  Assert-Admin
  $s = Load-State
  if (-not $s) { Write-Host "Nothing recorded in ${StateFile}: nothing to undo."; return }
  $User = $s.user      # always the account setup made, never a default: undoing stops that account's processes
  if (-not $User) { throw "The state file names no test account: not touching any account. Fix $StateFile by hand." }
  $log = Join-Path $Dir "revert.log"
  Start-Transcript -Path $log -Append | Out-Null
  $steps = @($s.steps); [array]::Reverse($steps)
  $sshAtEnd = ""     # restarting or removing sshd ends every SSH session, maybe this one: done last
  foreach ($st in $steps) {
    try {
      switch ($st.step) {
        "autologon" {
          $b = $st.data
          [KksLsa]::Store("DefaultPassword", $null)
          foreach ($n in "AutoAdminLogon", "DefaultUserName", "DefaultDomainName", "AutoLogonCount") {
            $v = $b.$n
            if ($null -eq $v) { Remove-ItemProperty $Winlogon $n -ErrorAction SilentlyContinue } else { Set-ItemProperty $Winlogon $n $v }
          }
          if ((RegValue $Winlogon "AutoAdminLogon") -ne "1") { Set-ItemProperty $Winlogon AutoAdminLogon "0" }
        }
        "firewall" { Get-NetFirewallRule -Group "KKS Explorer test" -ErrorAction SilentlyContinue | Remove-NetFirewallRule }
        "power" {
          $plans = (powercfg /list) -join " "
          if ($plans -match $st.data.original) { powercfg /setactive $st.data.original | Out-Null }
          if ($plans -match $st.data.plan) { powercfg /delete $st.data.plan | Out-Null }   # repeatable: gone already is fine
        }
        "shell" { Remove-ItemProperty "HKLM:\SOFTWARE\OpenSSH" DefaultShell -ErrorAction SilentlyContinue }
        "ssh" {
          $d = $st.data
          $before = Join-Path $Dir "sshd_config.before"
          if (Test-Path $before) { Copy-Item $before $SshConfig -Force }
          Get-NetFirewallRule -Name "kks-test-sshd" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
          if ($d.installed_before) {
            if ($d.rule_scope_before) { Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -RemoteAddress ($d.rule_scope_before -split ",") -ErrorAction SilentlyContinue }
            if ($d.start_type_before) { Set-Service sshd -StartupType $d.start_type_before }
            $sshAtEnd = "restart"
          } else { $sshAtEnd = "remove" }
        }
        "work" { if (-not $st.data.existed) { Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue } }
        "user" {
          Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like "*\$User" } | Stop-Process -Force -ErrorAction SilentlyContinue
          Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.Principal.UserId -like "*$User" } | Unregister-ScheduledTask -Confirm:$false
          $sid = (Get-LocalUser $User -ErrorAction SilentlyContinue).SID.Value
          if (-not $sid) { $sid = $s.user_sid }
          # the profile can stay loaded for a moment after its processes end (or until a restart)
          $gone = $false
          for ($i = 0; $i -lt 10 -and -not $gone; $i++) {
            $prof = Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid }
            if (-not $prof) { $gone = $true; break }
            try { $prof | Remove-CimInstance -ErrorAction Stop; $gone = $true } catch { Start-Sleep 2 }
          }
          if (-not $gone) { throw "the '$User' profile is still in use: restart the laptop, then run -Revert again" }
          Remove-LocalUser $User -ErrorAction SilentlyContinue
        }
      }
      Write-Host "undone: $($st.step)"
    } catch { Write-Host "COULD NOT UNDO $($st.step): $($_.Exception.Message)  (fix by hand, then run -Revert again)"; Stop-Transcript | Out-Null; return }
  }
  Remove-Item $StateFile, (Join-Path $Dir "authorized_keys"), (Join-Path $Dir "sshd_config.before") -ErrorAction SilentlyContinue
  if ($sshAtEnd) { Write-Host "last: OpenSSH ($sshAtEnd); an SSH session running this ends here" }
  Stop-Transcript | Out-Null
  if ($sshAtEnd -eq "restart") { Restart-Service sshd -ErrorAction SilentlyContinue }
  if ($sshAtEnd -eq "remove") {
    Stop-Service sshd -ErrorAction SilentlyContinue
    $cap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
    Remove-WindowsCapability -Online -Name $cap.Name | Out-Null
    Remove-Item "C:\ProgramData\ssh" -Recurse -Force -ErrorAction SilentlyContinue   # host keys made for the tests
  }
  Write-Host "All undone. Log: $log (delete C:\ProgramData\KKS-test when you no longer need it). Restart the laptop."
}

if ($Setup) { Do-Setup } elseif ($Revert) { Do-Revert } elseif ($Status) { Do-Status } else { Get-Help $PSCommandPath -Detailed }
