# Issue MCP JWT for a teammate (ricardo admin session required).
param(
  [string]$Teammate = "ana",
  [string]$ControlPlane = "http://127.0.0.1:8080",
  [string]$LanIp = ""
)

$ErrorActionPreference = "Stop"
if (-not $LanIp) {
  $LanIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like "192.168.*" } |
    Select-Object -First 1).IPAddress
}
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$ControlPlane/auth/dev-login?as=ricardo" -WebSession $session -UseBasicParsing
$r = Invoke-RestMethod -Uri "$ControlPlane/api/teammate-token/$Teammate" -WebSession $session

Write-Host ""
Write-Host "=== $Teammate handoff ===" -ForegroundColor Cyan
Write-Host "PLURIBUSAI_ENDPOINT=http://${LanIp}:30787"
Write-Host "PLURIBUSAI_TOKEN=$($r.access_token)"
Write-Host "PLURIBUSAI_USER=$($r.username)"
Write-Host ""
Write-Host "Or run on ana's PC:" -ForegroundColor Yellow
Write-Host "  .\install-teammate.ps1 -User $($r.username) -Token '<paste>' -Endpoint http://${LanIp}:30787"