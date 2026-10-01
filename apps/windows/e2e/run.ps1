# Run one UI script against a fresh KKS Explorer in this desktop session (started by a scheduled task, see e2e/README).
param([string]$Script, [switch]$Keep)
$log = "C:\kks\uia.log"
Set-Content $log ""
if (-not $Keep) {
  Get-Process KKSExplorer -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500
  Remove-Item -Recurse -Force "$env:LOCALAPPDATA\KKS Explorer" -ErrorAction SilentlyContinue
  $env:KKS_TRACE = "1"
  $env:KKS_TEST_PHOTO = "C:\kks\photo.jpg"      # the photo step picks this instead of a file dialog
  Start-Process C:\kks\KKSExplorer.exe
}
& C:\kks\uiadrive.exe KKSExplorer.exe "C:\kks\$Script" $log
Add-Content $log ("exit {0}" -f $LASTEXITCODE)
Add-Content $log "13:00:00 done"
