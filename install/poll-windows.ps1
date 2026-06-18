# Continuous long-poll daemon. WinRT toasts (Action Center), not legacy balloons.
$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
. (Join-Path $dir 'env.ps1')
$cache      = Join-Path $dir 'open-count.txt'
$cursorF    = Join-Path $dir '.activity-cursor'
$toastCurF  = Join-Path $dir '.last-toast-cursor'
$slfile     = Join-Path $dir 'statusline.txt'
$winrtPs1   = Join-Path $dir 'winrt-toast.ps1'
$pidF       = Join-Path $dir 'poll.pid'
$toastsOn   = -not ($PLURIBUSAI_TOASTS -eq '0')

if (Test-Path $pidF) {
  $oldPid = [int](Get-Content $pidF -ErrorAction SilentlyContinue)
  if ($oldPid -gt 0 -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { exit 0 }
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\PluribusAI.Poll.Daemon')
if (-not $mutex.WaitOne(0, $false)) { exit 0 }
Set-Content $pidF $PID

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }
if ($PLURIBUSAI_USER)   { $headers['X-PluribusAI-User'] = $PLURIBUSAI_USER }

function Get-CursorValue($path) {
  if (Test-Path $path) { return (Get-Content $path -Raw).Trim() }
  return '0'
}

function Set-CursorValue($path, $val) {
  [System.IO.File]::WriteAllText($path, "$val")
}

function Start-WinRTToast($text, $evt) {
  if (-not $toastsOn -or -not (Test-Path $winrtPs1)) { return }
  $payloadFile = Join-Path $dir ("toast-" + [guid]::NewGuid().ToString() + ".json")
  @{
    text = $text; type = $evt.type; message_id = $evt.message_id
    person = $evt.person; preview = $evt.preview
  } | ConvertTo-Json -Compress | Set-Content $payloadFile
  Start-Process -FilePath 'powershell' -ArgumentList @(
    '-Sta', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-WindowStyle', 'Hidden', '-File', $winrtPs1,
    '-PayloadFile', $payloadFile) -WindowStyle Hidden
}

function Refresh-Inbox {
  $body = @{ jsonrpc='2.0'; id=1; method='tools/call'; params=@{
    name='get_inbox'; arguments=@{} } } | ConvertTo-Json -Depth 6 -Compress
  try {
    $resp = Invoke-RestMethod -Uri "$PLURIBUSAI_ENDPOINT/mcp" -Method Post -Body $body `
      -Headers $headers -TimeoutSec 8
    $count = [int](($resp.result.content[0].text | ConvertFrom-Json).count)
    [System.IO.File]::WriteAllText($cache, "$count")
    if ($count -eq 0) { $txt = 'pluribusai: clear' } else { $txt = "pluribusai: $count new" }
    [System.IO.File]::WriteAllText($slfile, $txt, (New-Object System.Text.UTF8Encoding $false))
  } catch {
    [System.IO.File]::WriteAllText($cache, '?')
    [System.IO.File]::WriteAllText($slfile, 'pluribusai: ?', (New-Object System.Text.UTF8Encoding $false))
  }
}

$script:lastToastAt = [datetime]::MinValue

while ($true) {
  $cursor = Get-CursorValue $cursorF
  $actUri = "$PLURIBUSAI_ENDPOINT/activity?user=$PLURIBUSAI_USER&since=$cursor&timeout=30&limit=50"
  try {
    $act = Invoke-RestMethod -Uri $actUri -Method Get -Headers $headers -TimeoutSec 35
    $events = @($act.events)
    if ($events.Count -gt 0) {
      Set-CursorValue $cursorF $act.cursor

      $newCur = [double]$act.cursor
      $lastToastCur = [double](Get-CursorValue $toastCurF)
      $rateOk = ((Get-Date) - $script:lastToastAt).TotalSeconds -ge 10

      if ($toastsOn -and $rateOk -and ($newCur -gt $lastToastCur)) {
        $latest = $events[-1]
        if ($latest.type -eq 'reply') {
          $evt = @{ type='reply'; message_id=$latest.message_id; person=$latest.author; preview=$latest.preview }
          $toast = if ($events.Count -eq 1) {
            "$($latest.author) replied on $($latest.message_id)"
          } else {
            "$($events.Count) updates - latest: $($latest.author) on $($latest.message_id)"
          }
        } else {
          $evt = @{ type='message'; message_id=$latest.message_id; person=$latest.sender; preview=$latest.preview }
          $toast = if ($events.Count -eq 1) {
            "New message from $($latest.sender)"
          } else {
            "$($events.Count) new messages - latest from $($latest.sender)"
          }
        }
        Set-CursorValue $toastCurF $act.cursor
        $script:lastToastAt = Get-Date
        Start-WinRTToast $toast $evt
      }
    }
  } catch {}
  Refresh-Inbox
}