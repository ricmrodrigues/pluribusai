# Continuous long-poll daemon (like macOS launchd). Near-real-time toasts.
$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
. (Join-Path $dir 'env.ps1')
$cache     = Join-Path $dir 'open-count.txt'
$cursorF   = Join-Path $dir '.activity-cursor'
$slfile    = Join-Path $dir 'statusline.txt'
$toastPs1  = Join-Path $dir 'toast.ps1'
$pidF      = Join-Path $dir 'poll.pid'

# Single daemon instance.
$mutex = New-Object System.Threading.Mutex($false, 'Global\PluribusAI.Poll.Daemon')
if (-not $mutex.WaitOne(0, $false)) { exit 0 }
Set-Content $pidF $PID

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }
if ($PLURIBUSAI_USER)   { $headers['X-PluribusAI-User'] = $PLURIBUSAI_USER }

function Start-ToastAsync($text, $evt) {
  if (-not (Test-Path $toastPs1)) { return }
  $payloadFile = Join-Path $dir ("toast-" + [guid]::NewGuid().ToString() + ".json")
  $evt | ConvertTo-Json -Compress | Set-Content $payloadFile
  Start-Process -FilePath 'powershell' -ArgumentList @(
    '-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-WindowStyle', 'Hidden', '-File', $toastPs1,
    '-Text', $text, '-PayloadFile', $payloadFile) -WindowStyle Hidden
}

function Refresh-Inbox {
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
}

while ($true) {
  $cursor = 0.0
  if (Test-Path $cursorF) { $cursor = [double](Get-Content $cursorF) }
  $actUri = "$PLURIBUSAI_ENDPOINT/activity?user=$PLURIBUSAI_USER&since=$cursor&timeout=30&limit=50"
  try {
    $act = Invoke-RestMethod -Uri $actUri -Method Get -Headers $headers -TimeoutSec 35
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
      Start-ToastAsync $toast $evt
      [System.IO.File]::WriteAllText($cursorF, "$($act.cursor)")
    }
  } catch {}
  Refresh-Inbox
}