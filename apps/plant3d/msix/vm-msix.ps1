# Install or remove Walkdown Plant's MSIX in the logged-on user's session (test_msix_vm.py; an app deployment needs an
# interactive session, so this runs through apps/windows/e2e/runapp.ps1). The result goes to C:\plant\msix.log.
param([string]$Add = "", [switch]$Remove)
$log = "C:\plant\msix.log"
try {
  Get-AppxPackage WalkdownPlant | Remove-AppxPackage
  if ($Add) { Add-AppxPackage $Add }
  Set-Content $log ("ok " + (Get-AppxPackage WalkdownPlant).PackageFullName)
} catch {
  Set-Content $log ("failed " + $_.Exception.Message)
}
