# A contrast theme on or off for the desktop user, as Settings → Accessibility → Contrast themes does (the tests of
# #377: a contrast theme wins over the app's own dark colours). Run in the desktop session (runapp.ps1); writes
# C:\kks\contrast.log when done. -Scheme: the legacy name Windows maps to one of its contrast themes.
param([int]$On = 1, [string]$Scheme = "High Contrast White")
Add-Type @"
using System; using System.Runtime.InteropServices;
public class KksContrast {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct HIGHCONTRAST { public int cbSize; public int dwFlags; public string lpszDefaultScheme; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SystemParametersInfo(int a, int b, ref HIGHCONTRAST c, int d);
}
"@
$h = New-Object KksContrast+HIGHCONTRAST
$h.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type][KksContrast+HIGHCONTRAST])
$h.dwFlags = $(if ($On -eq 1) { 1 } else { 0 })     # HCF_HIGHCONTRASTON
$h.lpszDefaultScheme = $Scheme
# SPI_SETHIGHCONTRAST, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
$ok = [KksContrast]::SystemParametersInfo(0x43, $h.cbSize, [ref]$h, 3)
Set-Content C:\kks\contrast.log "contrast $On $ok"
