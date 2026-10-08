# Run one UI script against a fresh Walkdown in this desktop session (started by a scheduled task, see e2e/README).
param([string]$Script, [switch]$Keep, [switch]$Msix, [int]$SyncEvery = 0)
# -Msix: the installed MSIX (decision 0043), started through its alias; its LOCALAPPDATA lives in the package folder
$log = "C:\kks\uia.log"
Set-Content $log ""
if (-not $Keep) {
  Get-Process Walkdown -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500
  Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Walkdown" -ErrorAction SilentlyContinue
  Get-ChildItem "$env:LOCALAPPDATA\Packages\Walkdown_*\LocalCache\Local\Walkdown" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  $env:KKS_TRACE = "1"
  if ($SyncEvery -gt 0) { $env:KKS_SYNC_EVERY = "$SyncEvery" }   # automatic sync rounds every N ms (tests)
  $env:KKS_TEST_PHOTO = "C:\kks\photo.jpg"      # the photo step picks this instead of a file dialog
  $env:KKS_CAMERA_FILE = "C:\kks\qr.mp4"       # the scan window plays this through Media Foundation (no camera here)
  # the app's own output (sync results, errors) per script, for when a test fails
  $err = "C:\kks\app-" + [IO.Path]::GetFileNameWithoutExtension($Script) + ".log"
  if ($Msix) { Start-Process "$env:LOCALAPPDATA\Microsoft\WindowsApps\walkdown.exe" -RedirectStandardError $err }
  else { Start-Process C:\kks\Walkdown.exe -RedirectStandardError $err }
}
& C:\kks\uiadrive.exe Walkdown.exe "C:\kks\$Script" $log
Add-Content $log ("exit {0}" -f $LASTEXITCODE)
Add-Content $log "13:00:00 done"
