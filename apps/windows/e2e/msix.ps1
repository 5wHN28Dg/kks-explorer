# Install or remove the MSIX in the logged-on user's session (decision 0043). Add-AppxPackage over SSH fails with
# 0x80070005: an app deployment needs an interactive session. Started through runapp.ps1; the result goes to msix.log.
param([string]$Add = "", [switch]$Remove)
$log = "C:\kks\msix.log"
try {
  Get-AppxPackage KKSExplorer | Remove-AppxPackage
  if ($Add) { Add-AppxPackage $Add }
  Set-Content $log ("ok " + (Get-AppxPackage KKSExplorer).PackageFullName)
} catch {
  Set-Content $log ("failed " + $_.Exception.Message)
}
