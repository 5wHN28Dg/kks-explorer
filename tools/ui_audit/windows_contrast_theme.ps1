# UI audit: switch the "High Contrast Black" contrast theme on (-On 1) or off (-On 0) in the Windows VM, through
# SystemParametersInfo(SPI_SETHIGHCONTRAST). Run in the VM: powershell -File windows_contrast_theme.ps1 -On 1
param([int]$On = 1)
Add-Type @"
using System; using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct HC { public int cbSize; public int dwFlags; public IntPtr lpszDefaultScheme; }
public class HCSet { [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SystemParametersInfo(int a, int b, ref HC c, int d); }
"@
$h = New-Object HC
$h.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($h)
$h.dwFlags = if ($On) { 1 } else { 0 }
$h.lpszDefaultScheme = [Runtime.InteropServices.Marshal]::StringToHGlobalUni("High Contrast Black")
$r = [HCSet]::SystemParametersInfo(0x43, $h.cbSize, [ref]$h, 3)
Set-Content C:\kks\hc.log "set $On $r"
