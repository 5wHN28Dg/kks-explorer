# Run one UI script against a fresh Walkdown in this desktop session (started by a scheduled task, see e2e/README).
param([string]$Script, [switch]$Keep, [switch]$Msix, [int]$SyncEvery = 0, [switch]$Restart, [string]$AppEnv = "",
      [string]$AppArgs = "", [string]$Link = "", [switch]$Burst)
# -Msix: the installed MSIX (decision 0043), started through its alias; its LOCALAPPDATA lives in the package folder
# -Restart: a new process on the same data (what survives a restart); -AppEnv "K=V;K2=V2": extra environment for the app
# -AppArgs: the fresh app's command line (a walkdown:// link, decision 0057); -Link: a walkdown:// link opened before
# the script runs, as a second start of the exe (which hands it to the running app and ends), or with -Msix through
# the shell (the package's protocol activation); -Burst: the link opened twice at once (two starts racing)
$log = "C:\kks\uia.log"
Set-Content $log ""
if (-not $Keep) {
  Get-Process Walkdown -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500
  if (-not $Restart) {
    Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Walkdown" -ErrorAction SilentlyContinue
    Get-ChildItem "$env:LOCALAPPDATA\Packages\Walkdown_*\LocalCache\Local\Walkdown" -ErrorAction SilentlyContinue |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
  foreach ($kv in ($AppEnv -split ";")) { if ($kv -match "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$") { Set-Item "env:$($Matches[1])" $Matches[2] } }
  $env:KKS_TRACE = "1"
  if ($SyncEvery -gt 0) { $env:KKS_SYNC_EVERY = "$SyncEvery" }   # automatic sync rounds every N ms (tests)
  $env:KKS_TEST_PHOTO = "C:\kks\photo.jpg"      # the photo step picks this instead of a file dialog
  $env:KKS_CAMERA_FILE = "C:\kks\qr.mp4"       # the scan window plays this through Media Foundation (no camera here)
  # the app's own output (sync results, errors) per script, for when a test fails
  $err = "C:\kks\app-" + [IO.Path]::GetFileNameWithoutExtension($Script) + ".log"
  $extra = @{}
  if ($AppArgs) { $extra.ArgumentList = $AppArgs }
  if ($Msix) { Start-Process "$env:LOCALAPPDATA\Microsoft\WindowsApps\walkdown.exe" -RedirectStandardError $err @extra }
  else { Start-Process C:\kks\Walkdown.exe -RedirectStandardError $err @extra }
}
if ($Link -and $Burst) {
  if ($Msix) { Start-Process $Link; Start-Process $Link }
  else { Start-Process C:\kks\Walkdown.exe -ArgumentList $Link; Start-Process C:\kks\Walkdown.exe -ArgumentList $Link }
  Start-Sleep -Seconds 5
} elseif ($Link) {
  if ($Msix) { Start-Process $Link }
  else {
    $second = Start-Process C:\kks\Walkdown.exe -ArgumentList $Link -PassThru
    $second.WaitForExit(20000) | Out-Null
    Add-Content $log ("second start ended: {0}" -f $second.HasExited)
  }
  Start-Sleep -Seconds 2
}
& C:\kks\uiadrive.exe Walkdown.exe "C:\kks\$Script" $log
Add-Content $log ("exit {0}" -f $LASTEXITCODE)
Add-Content $log "13:00:00 done"
