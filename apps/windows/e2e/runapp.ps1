# Start a program in the logged-on user's desktop session (tests over SSH can't show windows themselves). Console
# programs go through conhost.exe: on Windows 11 the default-terminal handoff to Windows Terminal drops the arguments
# of a scheduled task (found on 26H2: an interactive cmd opened instead).
param([string]$Exe, [string]$ArgB64 = "", [string]$Name = "kksapp")
# the argument line comes base64-encoded (UTF-8): quotes do not survive SSH + the Windows command line
$ArgLine = if ($ArgB64) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgB64)) } else { "" }
$build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
if ($build -ge 22000 -and $Exe -match "(powershell|cmd)\.exe$") { $ArgLine = "$Exe $ArgLine"; $Exe = "conhost.exe" }   # Windows 11 only: 10's conhost ignores a command line
# Through the Task Scheduler's COM interface, not the ScheduledTasks cmdlets: those go through CIM (WMI), which a
# standard account is refused over SSH ("Cannot connect to CIM server. Access denied": the borrowed laptop's account,
# e2e/host, 2026-11-18). The same task as before: this user's interactive token, at most 30 minutes, instances in
# parallel, and (a laptop) started on battery too.
$svc = New-Object -ComObject Schedule.Service
$svc.Connect()
$t = $svc.NewTask(0)
$t.Settings.ExecutionTimeLimit = "PT30M"
$t.Settings.MultipleInstances = 0                 # TASK_INSTANCES_PARALLEL
$t.Settings.DisallowStartIfOnBatteries = $false
$t.Settings.StopIfGoingOnBatteries = $false
$t.Principal.UserId = "kks"
$t.Principal.LogonType = 3                        # TASK_LOGON_INTERACTIVE_TOKEN
$a = $t.Actions.Create(0)                         # TASK_ACTION_EXEC
$a.Path = $Exe
if ($ArgLine) { $a.Arguments = $ArgLine }
# TASK_CREATE_OR_UPDATE, no password, TASK_LOGON_INTERACTIVE_TOKEN
$task = $svc.GetFolder("\").RegisterTaskDefinition($Name, $t, 6, $null, $null, 3)
$task.Run($null) | Out-Null
