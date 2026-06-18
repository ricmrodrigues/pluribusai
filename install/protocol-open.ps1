# Handle pluribusai://open?type=message&message_id=...&person=...&preview=...
param([string]$Url = $args[0])
$ErrorActionPreference = 'SilentlyContinue'
if (-not $Url) { exit 1 }

$dir = Join-Path $env:USERPROFILE '.pluribusai'
$clickPy = Join-Path $dir 'click-handler.py'
. (Join-Path $dir 'env.ps1')
$python = if ($PLURIBUSAI_PYTHON) { $PLURIBUSAI_PYTHON } else { 'python' }

try {
  $uri = [Uri]$Url
  $qs = @{}
  foreach ($pair in $uri.Query.TrimStart('?').Split('&')) {
    if (-not $pair) { continue }
    $kv = $pair -split '=', 2
    if ($kv.Count -eq 2) { $qs[$kv[0]] = [Uri]::UnescapeDataString($kv[1]) }
  }
} catch { exit 1 }

$type = $qs['type']
$messageId = $qs['message_id']
$person = $qs['person']
$preview = $qs['preview']
if (-not $type -or -not $messageId) { exit 1 }

$args = @($clickPy, '--type', $type, '--message-id', $messageId, '--preview', $preview)
if ($type -eq 'reply') { $args += @('--author', $person) }
else { $args += @('--sender', $person) }

& $python @args