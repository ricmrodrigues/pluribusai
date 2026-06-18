$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
. (Join-Path $dir 'env.ps1')
$cache    = Join-Path $dir 'open-count.txt'
$cursorF  = Join-Path $dir '.activity-cursor'
$slfile   = Join-Path $dir 'statusline.txt'
$clickPy  = Join-Path $dir 'click-handler.py'

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }
if ($PLURIBUSAI_USER)   { $headers['X-PluribusAI-User'] = $PLURIBUSAI_USER }

function Show-Toast($text, $evt) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.Visible = $true
    if ($evt -and (Test-Path $clickPy)) {
      $n.Tag = $evt
      $handler = {
        param($source, $eventArgs)
        $t = $source.Tag
        if (-not $t) { return }
        $args = @(
          $clickPy,
          '--type', $t.type,
          '--message-id', $t.message_id,
          '--preview', $t.preview
        )
        if ($t.type -eq 'reply') { $args += '--author', $t.person }
        else { $args += '--sender', $t.person }
        Start-Process -FilePath 'python' -ArgumentList $args -WindowStyle Hidden
      }
      $n.add_BalloonTipClicked($handler)
    }
    $n.ShowBalloonTip(8000, 'PluribusAI', $text, 'Info')
    Start-Sleep -Seconds 9
    $n.Dispose()
  } catch {}
}

$cursor = 0.0
if (Test-Path $cursorF) { $cursor = [double](Get-Content $cursorF) }
$actUri = "$PLURIBUSAI_ENDPOINT/activity?user=$PLURIBUSAI_USER&since=$cursor&timeout=55&limit=50"
try {
  $act = Invoke-RestMethod -Uri $actUri -Method Get -Headers $headers -TimeoutSec 65
  foreach ($e in $act.events) {
    if ($e.type -eq 'reply') {
      $evt = @{
        type = 'reply'
        message_id = $e.message_id
        person = $e.author
        preview = $e.preview
      }
      Show-Toast "$($e.author) replied on $($e.message_id)" $evt
    } else {
      $evt = @{
        type = 'message'
        message_id = $e.message_id
        person = $e.sender
        preview = $e.preview
      }
      Show-Toast "New message from $($e.sender)" $evt
    }
  }
  if ($act.count -gt 0) {
    [System.IO.File]::WriteAllText($cursorF, "$($act.cursor)")
  }
} catch {}

$body = @{ jsonrpc='2.0'; id=1; method='tools/call'; params=@{
  name='get_inbox'; arguments=@{} } } | ConvertTo-Json -Depth 6 -Compress
try {
  $resp = Invoke-RestMethod -Uri "$PLURIBUSAI_ENDPOINT/mcp" -Method Post -Body $body `
    -Headers $headers -TimeoutSec 8
  $count = [int](($resp.result.content[0].text | ConvertFrom-Json).count)
  [System.IO.File]::WriteAllText($cache, "$count")
  if ($count -eq 0) { $txt = 'pluribusai: clear' }
  else { $txt = "pluribusai: $count new" }
  [System.IO.File]::WriteAllText($slfile, $txt, (New-Object System.Text.UTF8Encoding $false))
} catch {
  [System.IO.File]::WriteAllText($cache, '?')
  [System.IO.File]::WriteAllText($slfile, 'pluribusai: ?', (New-Object System.Text.UTF8Encoding $false))
}