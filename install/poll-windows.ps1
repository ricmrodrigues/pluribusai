$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
. (Join-Path $dir 'env.ps1')
$cache    = Join-Path $dir 'open-count.txt'
$cursorF  = Join-Path $dir '.activity-cursor'
$slfile   = Join-Path $dir 'statusline.txt'
$clickPy  = Join-Path $dir 'click-handler.py'
$lockF    = Join-Path $dir '.poll.lock'
$python   = if ($PLURIBUSAI_PYTHON) { $PLURIBUSAI_PYTHON } else { 'python' }

if (Test-Path $lockF) {
  $age = (Get-Date) - (Get-Item $lockF).LastWriteTime
  if ($age.TotalSeconds -lt 45) { exit 0 }
}
Set-Content $lockF (Get-Date -Format o)

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }
if ($PLURIBUSAI_USER)   { $headers['X-PluribusAI-User'] = $PLURIBUSAI_USER }

function Invoke-ClickHandler($evt) {
  if (-not $evt -or -not (Test-Path $clickPy)) { return }
  $py = if (Test-Path $python) { $python } else { 'python' }
  $payload = @{
    type = $evt.type
    message_id = $evt.message_id
    person = $evt.person
    preview = $evt.preview
  } | ConvertTo-Json -Compress
  $payloadFile = Join-Path $dir 'click-payload.json'
  [System.IO.File]::WriteAllText($payloadFile, $payload)
  & $py $clickPy --payload-file $payloadFile
}

function Show-Toast($text, $evt) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $script:toastClicked = $false
    $script:clickEvt = $null
    $script:clickDone = $false
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.Visible = $true
    if ($evt) {
      $n.Tag = $evt
      $markClick = {
        param($source, $eventArgs)
        if ($script:toastClicked) { return }
        $script:toastClicked = $true
        $script:clickEvt = $source.Tag
      }
      $n.add_BalloonTipClicked($markClick)
      $n.add_Click($markClick)
    }
    $n.ShowBalloonTip(15000, 'PluribusAI', "$text`n(Click balloon or tray icon)", 'Info')
    $deadline = (Get-Date).AddSeconds(18)
    while ((Get-Date) -lt $deadline) {
      if ($script:toastClicked -and -not $script:clickDone) {
        $script:clickDone = $true
        Invoke-ClickHandler $script:clickEvt
        break
      }
      [System.Windows.Forms.Application]::DoEvents()
      Start-Sleep -Milliseconds 200
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