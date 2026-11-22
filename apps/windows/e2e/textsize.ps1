# Windows' text size set as a person does it, in Settings (Accessibility → Text size; Windows 10: Ease of Access →
# Display → Make text bigger): the slider to -Percent, then Apply (the tests of #377). Run in the desktop session
# (runapp.ps1); writes C:\kks\textsize.log (the driver's log) and ends Settings. Its window belongs to
# ApplicationFrameHost.exe (a UWP app's frame), where the driver looks for it.
param([int]$Percent = 100, [string]$Slider = "Text size")
$script = "C:\kks\textsize.uia"
Set-Content -Path $script -Encoding ascii -Value @("wait`t$Slider`t30", "range`t$Slider`t$Percent", "sleep`t500", "click`tApply", "sleep`t8000")
Remove-Item C:\kks\textsize.log, C:\kks\textsize.drv.log -ErrorAction SilentlyContinue
Start-Process "ms-settings:easeofaccess-display"
Start-Sleep -Seconds 3
& C:\kks\uiadrive.exe ApplicationFrameHost.exe $script C:\kks\textsize.drv.log
Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force
Copy-Item C:\kks\textsize.drv.log C:\kks\textsize.log
