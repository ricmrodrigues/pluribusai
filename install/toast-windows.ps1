# Show one toast (STA). Spawned by poll daemon so long-poll is not blocked.
param(
  [Parameter(Mandatory)][string]$PayloadFile
)
$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
. (Join-Path $dir 'env.ps1')
$clickPy = Join-Path $dir 'click-handler.py'
$python  = if ($PLURIBUSAI_PYTHON) { $PLURIBUSAI_PYTHON } else { 'python' }
$data = Get-Content $PayloadFile -Raw | ConvertFrom-Json
$Text = $data.text
$evt = $data

function Invoke-ClickHandler($e) {
  if (-not $e -or -not (Test-Path $clickPy)) { return }
  $py = if (Test-Path $python) { $python } else { 'python' }
  $payload = @{
    type = $e.type
    message_id = $e.message_id
    person = $e.person
    preview = $e.preview
  } | ConvertTo-Json -Compress
  $pf = Join-Path $dir 'click-payload.json'
  [System.IO.File]::WriteAllText($pf, $payload)
  & $py $clickPy --payload-file $pf
}

Add-Type -AssemblyName System.Windows.Forms
$script:clicked = $false
$script:clickEvt = $null
$script:shownAt = Get-Date

function Register-Click($source) {
  $onTray = {
    param($src, $eventArgs)
    if ($eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($script:clicked) { return }
    if (((Get-Date) - $script:shownAt).TotalMilliseconds -lt 400) { return }
    $script:clicked = $true
    $script:clickEvt = $src.Tag
  }
  $onBalloon = {
    param($src, $eventArgs)
    if ($script:clicked) { return }
    $elapsed = ((Get-Date) - $script:shownAt).TotalSeconds
    # Ignore auto-dismiss ghost clicks (usually fire near balloon timeout).
    if ($elapsed -lt 0.4 -or $elapsed -gt 11) { return }
    $script:clicked = $true
    $script:clickEvt = $src.Tag
  }
  $source.add_MouseClick($onTray)
  $source.add_BalloonTipClicked($onBalloon)
}

$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = [System.Drawing.SystemIcons]::Information
$n.Text = 'PluribusAI - click to open in Cursor'
$n.Visible = $true
$n.Tag = $evt
Register-Click $n
$n.ShowBalloonTip(12000, 'PluribusAI', "$Text`n(Click balloon or tray icon)", 'Info')
$deadline = (Get-Date).AddSeconds(18)
while ((Get-Date) -lt $deadline) {
  if ($script:clicked) {
    Invoke-ClickHandler $script:clickEvt
    break
  }
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 200
}
$n.Dispose()
Remove-Item $PayloadFile -ErrorAction SilentlyContinue