# Run in the VM while Walkdown runs: powershell -File windows_uiadump.ps1 -Tag NAME (an alternative to the patched
# uiadrive dump that windows_audit.py uses).
# UI audit: every UIA element of Walkdown's windows with type, name, rectangle, focusable, offscreen -> C:\kks\dump-<Tag>.tsv
param([string]$Tag = "x")
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$proxies = [System.Reflection.Assembly]::LoadWithPartialName("UIAutomationClientsideProviders")
[System.Windows.Automation.ClientSettings]::RegisterClientSideProviderAssembly($proxies.GetName())
$E = [System.Windows.Automation.AutomationElement]
$out = "C:\kks\dump-$Tag.tsv"
$lines = New-Object System.Collections.Generic.List[string]
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Dpi { [DllImport("user32.dll")] public static extern int GetDpiForSystem(); }
"@
$lines.Add("dpi`t" + [Dpi]::GetDpiForSystem())
foreach ($p in Get-Process Walkdown -ErrorAction SilentlyContinue) {
  $c = New-Object System.Windows.Automation.PropertyCondition ($E::ProcessIdProperty, $p.Id)
  foreach ($w in $E::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $c)) {
    $lines.Add("WINDOW`t" + $w.Current.Name + "`t" + $w.Current.BoundingRectangle)
    foreach ($e in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
      try {
        $r = $e.Current.BoundingRectangle
        $lines.Add(("{0}`t{1}`t{2},{3},{4},{5}`t{6}`t{7}`t{8}" -f $e.Current.ControlType.ProgrammaticName, ($e.Current.Name -replace "`t|`r|`n", " "),
          [int]$r.Left, [int]$r.Top, [int]$r.Width, [int]$r.Height, $e.Current.IsKeyboardFocusable, $e.Current.IsOffscreen, $e.Current.AccessKey))
      } catch {}
    }
  }
}
[IO.File]::WriteAllLines($out, $lines, [Text.Encoding]::UTF8)
Set-Content "C:\kks\dump-$Tag.done" "ok"
