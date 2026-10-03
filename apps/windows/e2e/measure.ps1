# docs/m6/MEASUREMENTS.md, Windows: 5 starts of the joined app; startup from timing.log, private bytes after 15 s.
$log = "C:\kks\uia.log"
Set-Content $log ""
$data = Join-Path $env:LOCALAPPDATA "Walkdown"
Remove-Item (Join-Path $data "timing.log") -ErrorAction SilentlyContinue
$env:KKS_TIMING = "1"
for ($i = 1; $i -le 5; $i++) {
  Get-Process Walkdown -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep 2
  $p = Start-Process C:\kks\Walkdown.exe -PassThru
  Start-Sleep 15
  $p.Refresh()
  Add-Content $log ("run {0}: private {1:N1} MB, working set {2:N1} MB" -f $i, ($p.PrivateMemorySize64 / 1MB), ($p.WorkingSet64 / 1MB))
}
Get-Process Walkdown -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Content (Join-Path $data "timing.log") | ForEach-Object { Add-Content $log $_ }
Add-Content $log ("exe {0:N2} MB" -f ((Get-Item C:\kks\Walkdown.exe).Length / 1MB))
Add-Content $log "13:00:00 done"
