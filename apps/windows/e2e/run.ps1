# Run one UI script against a fresh KKS Explorer in this desktop session (started by a scheduled task, see e2e/README).
param([string]$Script, [switch]$Keep, [switch]$Msix)
# -Msix: the installed MSIX (decision 0043), started through its alias; its LOCALAPPDATA lives in the package folder
$log = "C:\kks\uia.log"
Set-Content $log ""
if (-not $Keep) {
  Get-Process KKSExplorer -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500
  Remove-Item -Recurse -Force "$env:LOCALAPPDATA\KKS Explorer" -ErrorAction SilentlyContinue
  Get-ChildItem "$env:LOCALAPPDATA\Packages\KKSExplorer_*\LocalCache\Local\KKS Explorer" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  $env:KKS_TRACE = "1"
  $env:KKS_TEST_PHOTO = "C:\kks\photo.jpg"      # the photo step picks this instead of a file dialog
  $env:KKS_CAMERA_FILE = "C:\kks\qr.mp4"       # the scan window plays this through Media Foundation (no camera here)
  # the app's own output (sync results, errors) per script, for when a test fails
  $err = "C:\kks\app-" + [IO.Path]::GetFileNameWithoutExtension($Script) + ".log"
  if ($Msix) { Start-Process "$env:LOCALAPPDATA\Microsoft\WindowsApps\kks-explorer.exe" -RedirectStandardError $err }
  else { Start-Process C:\kks\KKSExplorer.exe -RedirectStandardError $err }
}
& C:\kks\uiadrive.exe KKSExplorer.exe "C:\kks\$Script" $log
Add-Content $log ("exit {0}" -f $LASTEXITCODE)
Add-Content $log "13:00:00 done"
