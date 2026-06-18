$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
. (Join-Path $dir 'env.ps1')
$cache    = Join-Path $dir 'open-count.txt'
$cursorF  = Join-Path $dir '.activity-cursor'
$slfile   = Join-Path $dir 'statusline.txt'
$clickPy  = Join-Path $dir 'click-handler.py'
$lockF    = Join-Path $dir '.poll.lock'

# Skip if another poller ran in the last 45s (manual + scheduled overlap).
if (Test-Path $lockF) {
  $age = (Get-Date) - (Get-Item $lockF).LastWriteTime
  if ($age.TotalSeconds -lt 45) { exit 0 }
}
Set-Content $lockF (Get-Date -Format o)

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }
if ($PLURIBUSAI_USER)   { $headers['X-PluribusAI-User'] = $PLURIBUSAI_USER }

$global:PluribusClickPy = $clickPy
$global:PluribusDir = $dir

function Show-Toast($text, $evt) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $script:toastClicked = $false
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.Visible = $true
    if ($evt) {
      $n.Tag = $evt
      $onClick = {
        param($source, $eventArgs)
        if ($script:toastClicked) { return }
        $script:toastClicked = $true
        $t = $source.Tag
        if (-not $t) { return }
        $py = $global:PluribusClickPy
        $pdir = $global:PluribusDir
        if (-not (Test-Path $py)) { return }
        $payload = @{
          type = $t.type
          message_id = $t.message_id
          person = $t.person
          preview = $t.preview
        } | ConvertTo-Json -Compress
        $payloadFile = Join-Path $pdir 'click-payload.json'
        [System.IO.File]::WriteAllText($payloadFile, $payload)
        Start-Process -FilePath 'python' -ArgumentList @(
          $py, '--payload-file', $payloadFile) -WindowStyle Hidden
      }
      $n.add_BalloonTipClicked($onClick)
      $n.add_Click($onClick)
    }
    $n.ShowBalloonTip(12000, 'PluribusAI', "$text`n(Click balloon or tray icon)", 'Info')
    $deadline = (Get-Date).AddSeconds(14)
    while ((Get-Date) -lt $deadline -and -not $script:toastClicked) {
      [System.Windows.Forms.Application]::DoEvents()
      Start-Sleep -Milliseconds 250
    }
    $n.Dispose()
  } catch {}
}

$cursor = 0.0
if (Test-Path $cursorF) { $cursor = [double](Get-Content $cursorF) }
$actUri = "$PLURIBUSAI_ENDPOINT/activity?user=$PLURIBUSAI_USER&since=$cursor&timeout=55&limit=50"
try {
  $act = Invoke-RestMethod -Uri $actUri -Method Get -Headers $headers -TimeoutSec 65
  $events = @($act.events)
  if ($events.Count -gt 0) {
    # One toast per poll: summarize batch, click opens the newest event.
    $latest = $events[-1]
    if ($latest.type -eq 'reply') {
      $evt = @{
        type = 'reply'
        message_id = $latest.message_id
        person = $latest.author
        preview = $latest.preview
      }
      if ($events.Count -eq 1) {
        $toast = "$($latest.author) replied on $($latest.message_id)"
      } else {
        $toast = "$($events.Count) updates - latest: $($latest.author) on $($latest.message_id)"
      }
    } else {
      $evt = @{
        type = 'message'
        message_id = $latest.message_id
        person = $latest.sender
        preview = $latest.preview
      }
      if ($events.Count -eq 1) {
        $toast = "New message from $($latest.sender)"
      } else {
        $toast = "$($events.Count) new messages - latest from $($latest.sender)"
      }
    }
    Show-Toast $toast $evt
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