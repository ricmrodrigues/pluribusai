# Fetch JWT from control plane and update ~/.pluribusai/env.ps1
param(
  [string]$User = "ricardo",
  [string]$ControlPlane = "http://127.0.0.1:8080",
  [string]$DataPlane = "http://localhost:30787",
  [string]$EnvFile = "$HOME\.pluribusai\env.ps1"
)

$ErrorActionPreference = "Stop"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$ControlPlane/auth/dev-login?as=$User" -WebSession $session -UseBasicParsing
$tok = Invoke-RestMethod -Uri "$ControlPlane/api/token" -WebSession $session

$lines = @(
  "`$PLURIBUSAI_TOKEN    = '$($tok.access_token)'"
  "`$PLURIBUSAI_ENDPOINT = '$DataPlane'"
  "`$PLURIBUSAI_USER     = '$($tok.username)'"
  "`$PLURIBUSAI_PYTHON   = 'C:\Users\ricmr\AppData\Local\Programs\Python\Python313\python.exe'"
  "`$PLURIBUSAI_FOCUS_APP = 'cursor,grok'"
  "# Wired from control plane $(Get-Date -Format o)"
)
Set-Content -Path $EnvFile -Value ($lines -join "`n") -Encoding UTF8
Write-Host "Updated $EnvFile for user $($tok.username)"
Write-Host "Restart poll daemon if running: stop old PID, run poll-windows.ps1"