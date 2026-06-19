# Expose PluribusAI on LAN via NodePort + optional Windows firewall rule.
param(
  [string]$Namespace = "pluribusai",
  [int]$NodePort = 30787,
  [switch]$AddFirewallRule,
  [switch]$SkipHelm
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Chart = Join-Path $Root "deploy\helm\pluribusai"

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
  Select-Object -First 1).IPAddress
if (-not $ip) { $ip = "127.0.0.1" }

if (-not $SkipHelm) {
  Say "Patching service to NodePort $NodePort..."
  helm upgrade pluribusai $Chart -n $Namespace `
    --reuse-values `
    --set service.type=NodePort `
    --set service.nodePort=$NodePort `
    --wait --timeout 3m
}

Say "LAN endpoint: http://${ip}:${NodePort}"
Say "MCP:          http://${ip}:${NodePort}/mcp"
Say "Health:       http://${ip}:${NodePort}/health"

if ($AddFirewallRule) {
  $rule = "PluribusAI NodePort $NodePort"
  if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    Say "Adding firewall rule (admin)..."
    netsh advfirewall firewall add rule name="$rule" dir=in action=allow protocol=TCP localport=$NodePort | Out-Null
  } else {
    Say "Firewall rule already exists."
  }
}

Write-Host ""
Write-Host "Teammate install:" -ForegroundColor Yellow
Write-Host "  PLURIBUSAI_ENDPOINT=http://${ip}:${NodePort}"
Write-Host "  PLURIBUSAI_TOKEN=<api-key-or-jwt>"
Write-Host "  PLURIBUSAI_USER=<username>"