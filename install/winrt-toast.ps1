# WinRT Action Center toast (replaces legacy NotifyIcon balloons).
param([Parameter(Mandatory)][string]$PayloadFile)
$ErrorActionPreference = 'SilentlyContinue'
$aumid = 'PluribusAI.TeamInbox'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
$envFile = Join-Path $dir 'env.ps1'
if (Test-Path $envFile) { . $envFile }
$clickPy = Join-Path $dir 'click-handler.py'
$python = if ($PLURIBUSAI_PYTHON) { $PLURIBUSAI_PYTHON } else { 'python' }
$attribution = 'Click to open agent app'
if (Test-Path $clickPy) {
  $line = & $python $clickPy --focus-attribution 2>$null
  if ($line) { $attribution = $line.Trim() }
}

$data = Get-Content $PayloadFile -Raw | ConvertFrom-Json
$type = $data.type
$messageId = $data.message_id
$person = $data.person
$preview = [string]$data.preview
$title = [string]$data.text

function Escape-Xml($s) {
  if (-not $s) { return '' }
  return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

$q = @{
  type = $type
  message_id = $messageId
  person = $person
  preview = $preview
}
$launch = 'pluribusai://open?' + (($q.GetEnumerator() | ForEach-Object {
  "$($_.Key)=$([Uri]::EscapeDataString([string]$_.Value))"
}) -join '&')

$tag = "pluribusai:$messageId"
$xml = @"
<toast activationType="protocol" launch="$(Escape-Xml $launch)" tag="$(Escape-Xml $tag)" scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>PluribusAI</text>
      <text>$(Escape-Xml $title)</text>
      <text placement="attribution">$(Escape-Xml $attribution)</text>
    </binding>
  </visual>
</toast>
"@

try {
  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
  $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
  $doc.LoadXml($xml)
  $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
  $toast.Tag = $tag
  $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid)
  $notifier.Show($toast)
} catch {
  exit 1
}
Remove-Item $PayloadFile -ErrorAction SilentlyContinue