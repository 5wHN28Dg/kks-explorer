# docs/m6/MEASUREMENTS.md "Startup" (tools/m6/startup_windows.py runs it in the desktop session): joins a data folder
# for each exe (C:\kks\startup_join.exe, e2e/startup_join.nim) through the server, then starts the exes in turns,
# RUNS times each after one warm-up start, each with KKS_TIMING=1 and stopped after WAIT s. Their timing.log lines
# go to C:\kks\startup.log.
param([string]$Server, [string]$Exes, [int]$Runs = 7, [int]$Wait = 12)
$log = "C:\kks\startup.log"
Set-Content $log ""
$list = $Exes.Split(",")
function Folder($e) { "C:\kks\sd-" + [IO.Path]::GetFileNameWithoutExtension($e) }
foreach ($e in $list) {
  $d = Folder $e
  Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory $d | Out-Null
  $env:KKS_DATA_DIR = $d
  $p = Start-Process C:\kks\startup_join.exe -ArgumentList "$Server boss `"a long password`"" -PassThru -Wait
  Add-Content $log ("{0} join: exit {1} {2}" -f $e, $p.ExitCode, (Get-Content (Join-Path $d "startup_join.txt") -ErrorAction SilentlyContinue))
}
$env:KKS_TIMING = "1"
for ($i = 0; $i -le $Runs; $i++) {
  foreach ($e in $list) {
    $d = Folder $e
    $env:KKS_DATA_DIR = $d
    Start-Sleep 2
    $p = Start-Process $e -PassThru
    Start-Sleep $Wait
    Stop-Process -Id $p.Id -Force
    Add-Content (Join-Path $d "timing.log") "end of run $i"
  }
}
foreach ($e in $list) {
  Add-Content $log "== $e"
  Get-Content (Join-Path (Folder $e) "timing.log") | ForEach-Object { Add-Content $log $_ }
}
Add-Content $log "13:00:00 done"
