# Start a program in the logged-on user's desktop session (tests over SSH can't show windows themselves). Console
# programs go through conhost.exe: on Windows 11 the default-terminal handoff to Windows Terminal drops the arguments
# of a scheduled task (found on 26H2: an interactive cmd opened instead).
param([string]$Exe, [string]$ArgB64 = "", [string]$Name = "kksapp")
# the argument line comes base64-encoded (UTF-8): quotes do not survive SSH + the Windows command line
$ArgLine = if ($ArgB64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgB64)) } else { "" }
$build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
if ($build -ge 22000 -and $Exe -match "(powershell|cmd)\.exe$") { $ArgLine = "$Exe $ArgLine"; $Exe = "conhost.exe" }   # Windows 11 only: 10's conhost ignores a command line
$a = if ($ArgLine) { New-ScheduledTaskAction -Execute $Exe -Argument $ArgLine } else { New-ScheduledTaskAction -Execute $Exe }
$p = New-ScheduledTaskPrincipal -UserId "kks" -LogonType Interactive
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances Parallel
Register-ScheduledTask -TaskName $Name -Action $a -Principal $p -Settings $s -Force | Out-Null
Start-ScheduledTask -TaskName $Name
