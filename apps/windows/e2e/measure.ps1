# docs/m6/MEASUREMENTS.md, Windows: RUNS starts of the joined app; startup from timing.log, private bytes after WAIT s.
#   measure.ps1 [-Exe C:\kks\Walkdown.exe] [-Data folder] [-Runs 5] [-Wait 15] [-Log C:\kks\uia.log]
# -Data: the app's data folder (KKS_DATA_DIR; e2e/startup_join.nim joins one), else its default one.
param([string]$Exe = "C:\kks\Walkdown.exe", [string]$Data = "", [int]$Runs = 5, [int]$Wait = 15,
      [string]$Log = "C:\kks\uia.log")
Set-Content $Log ""
if ($Data -ne "") { $env:KKS_DATA_DIR = $Data } else { $Data = Join-Path $env:LOCALAPPDATA "Walkdown" }
Remove-Item (Join-Path $Data "timing.log") -ErrorAction SilentlyContinue
$env:KKS_TIMING = "1"
for ($i = 1; $i -le $Runs; $i++) {
  Start-Sleep 2
  $p = Start-Process $Exe -PassThru
  Start-Sleep $Wait
  $p.Refresh()
  Add-Content $Log ("run {0}: private {1:N1} MB, working set {2:N1} MB" -f $i, ($p.PrivateMemorySize64 / 1MB), ($p.WorkingSet64 / 1MB))
  Stop-Process -Id $p.Id -Force
  Add-Content (Join-Path $Data "timing.log") "end of run $i"
}
Get-Content (Join-Path $Data "timing.log") | ForEach-Object { Add-Content $Log $_ }
Add-Content $Log ("exe {0:N2} MB" -f ((Get-Item $Exe).Length / 1MB))
Add-Content $Log "13:00:00 done"
