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
$clicked = $false
$clickEvt = $null
$shownAt = Get-Date
$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = [System.Drawing.SystemIcons]::Information
$n.Text = 'PluribusAI - click icon to open'
$n.Visible = $true
$n.Tag = $evt
$onTrayClick = {
  param($source, $eventArgs)
  if ($eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  if ($script:clicked) { return }
  if (((Get-Date) - $shownAt).TotalMilliseconds -lt 400) { return }
  $script:clicked = $true
  $script:clickEvt = $source.Tag
}
$n.add_MouseClick($onTrayClick)
$n.ShowBalloonTip(8000, 'PluribusAI', "$Text`n(Click the blue icon in the tray)", 'Info')
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
  if ($clicked) {
    Invoke-ClickHandler $clickEvt
    break
  }
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 200
}
$n.Dispose()
Remove-Item $PayloadFile -ErrorAction SilentlyContinue