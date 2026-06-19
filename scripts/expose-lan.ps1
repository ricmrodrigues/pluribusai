# Expose PluribusAI on the LAN via Kubernetes NodePort (Docker Desktop).
# Usage: .\scripts\expose-lan.ps1 [-User ana]
param(
  [string]$User = "ana",
  [int]$NodePort = 30787
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Chart = Join-Path $Root "deploy\helm\pluribusai"

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

Say "Upgrading pluribusai service to NodePort $NodePort..."
helm upgrade pluribusai $Chart -n pluribusai --reuse-values `
  --set service.type=NodePort `
  --set service.nodePort=$NodePort `
  --wait --timeout 3m

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object {
    $_.IPAddress -match '^(192\.168\.|10\.)' -and
    $_.InterfaceAlias -notmatch 'VPN|Nord|Proton|WSL|Hyper-V|Loopback'
  } |
  Sort-Object @{ Expression = { $_.IPAddress -like '192.168.*' }; Descending = $true } |
  Select-Object -First 1 -ExpandProperty IPAddress)
if (-not $ip) {
  $ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like '192.168.*' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
}

if (-not $ip) { $ip = "<your-lan-ip>" }

$token = kubectl get secret pluribusai -n pluribusai `
  -o jsonpath="{.data.PLURIBUSAI_TOKEN}" 2>$null
if ($token) {
  $token = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($token))
} else {
  $token = "<token-from-kubectl-get-secret>"
}

$endpoint = "http://${ip}:${NodePort}"

Say "LAN endpoint: $endpoint"
Say "Bearer token:   $token"
Write-Host ""
Write-Host "On ${User}'s machine (Git Bash or WSL):" -ForegroundColor Yellow
Write-Host @"
  PLURIBUSAI_ENDPOINT=$endpoint \
  PLURIBUSAI_TOKEN=$token \
  PLURIBUSAI_USER=$User \
  ./install-cursor.sh
"@

Say "Test from this machine:"
Write-Host "  curl http://localhost:${NodePort}/health"
Write-Host ""
Say "If ${User} cannot connect, allow inbound TCP $NodePort in Windows Firewall."