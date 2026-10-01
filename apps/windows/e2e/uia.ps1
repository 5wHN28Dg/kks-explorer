# Driving the Windows app the way Narrator sees it: through UI Automation (decision 0033). Dot-source this file.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
# the Win32 control proxies (Button, Edit, List…): the managed client needs them registered, the native UIA core
# (Narrator) has them built in
$proxies = [System.Reflection.Assembly]::LoadWithPartialName("UIAutomationClientsideProviders")
[System.Windows.Automation.ClientSettings]::RegisterClientSideProviderAssembly($proxies.GetName())
$UiaEl = [System.Windows.Automation.AutomationElement]
$UiaScope = [System.Windows.Automation.TreeScope]
$UiaCond = [System.Windows.Automation.PropertyCondition]

function Log($msg) { Add-Content -Path $global:UiaLog -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $msg) }

function Get-AppWindow([int]$procId, [int]$timeout = 20) {
  $end = (Get-Date).AddSeconds($timeout)
  while ((Get-Date) -lt $end) {
    $c = New-Object $UiaCond ($UiaEl::ProcessIdProperty, $procId)
    $w = $UiaEl::RootElement.FindFirst($UiaScope::Children, $c)
    if ($w) { return $w }
    Start-Sleep -Milliseconds 300
  }
  throw "no window for process $procId"
}

function Find-El($root, [string]$name, [switch]$Contains, [int]$timeout = 15, [string]$type = "") {
  $end = (Get-Date).AddSeconds($timeout)
  while ((Get-Date) -lt $end) {
    $all = $root.FindAll($UiaScope::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $all) {
      try {
        $n = $e.Current.Name
        if ($type -and $e.Current.ControlType.ProgrammaticName -ne ("ControlType." + $type)) { continue }
        if (($Contains -and $n -and $n.Contains($name)) -or (-not $Contains -and $n -eq $name)) { return $e }
      } catch {}
    }
    Start-Sleep -Milliseconds 400
  }
  throw "not found: $name"
}

function Click($el) {
  $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Set-Text($el, [string]$text) {
  $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($text)
}

function Dump($root, [int]$max = 400) {
  $all = $root.FindAll($UiaScope::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $i = 0
  foreach ($e in $all) {
    if ($i++ -ge $max) { break }
    try { Log ("  {0} '{1}'" -f $e.Current.ControlType.ProgrammaticName, $e.Current.Name) } catch {}
  }
}
