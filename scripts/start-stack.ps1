# Start full local stack: control plane + verify k8s + wire ricardo client.
param(
  [switch]$SkipK8sWire,
  [switch]$SkipClient,
  [string]$JwtSecret = "pluribusai-cloud-jwt-secret-change-me-32ch"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Cloud = "C:\code\pluribusai-cloud"

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

# Control plane
$cpUp = $false
try {
  $r = Invoke-RestMethod -Uri "http://127.0.0.1:8080/health" -TimeoutSec 2
  $cpUp = $r.status -eq "ok"
} catch {}
if (-not $cpUp) {
  Say "Starting control plane..."
  $env:PYTHONPATH = $Cloud
  $env:CONTROL_PLANE_SECRET = $JwtSecret
  $env:CONTROL_PLANE_URL = "http://localhost:8080"
  $env:DATA_PLANE_URL = "http://localhost:30787"
  $env:PLURIBUSAI_INTERNAL_SECRET = $JwtSecret
  Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList @(
    "-NoProfile", "-Command",
    "cd '$Cloud'; `$env:PYTHONPATH='.'; `$env:CONTROL_PLANE_SECRET='$JwtSecret'; " +
    "`$env:DATA_PLANE_URL='http://localhost:30787'; `$env:PLURIBUSAI_INTERNAL_SECRET='$JwtSecret'; " +
    "uvicorn control_plane.app:app --host 127.0.0.1 --port 8080"
  )
  Start-Sleep 3
}

# K8s data plane
try {
  $dp = Invoke-RestMethod -Uri "http://localhost:30787/health" -TimeoutSec 3
  Say "Data plane: v$($dp.version) auth=$($dp.auth) jwt=$($dp.jwt)"
} catch {
  Write-Warning "Data plane not reachable on :30787 — run helm install or wire-cloud.ps1"
}

if (-not $SkipK8sWire) {
  $dpJwt = (Invoke-RestMethod -Uri "http://localhost:30787/health" -TimeoutSec 2).jwt
  if ($dpJwt -ne "on") {
    Say "Wiring k8s JWT auth..."
    & "$Root\scripts\wire-cloud.ps1" -JwtSecret $JwtSecret -ExistingToken "pk_a1358aa7b798479a9eeaf8c07dd7dc68"
  }
}

if (-not $SkipClient) {
  Say "Wiring ricardo client + Cursor MCP..."
  & "$Root\scripts\wire-client.ps1" -User ricardo
  & "$Root\scripts\wire-cursor-mcp.ps1"
  if (Test-Path "$HOME\.pluribusai\poll.pid") {
    $old = Get-Content "$HOME\.pluribusai\poll.pid" -ErrorAction SilentlyContinue
    if ($old) { Stop-Process -Id $old -Force -ErrorAction SilentlyContinue }
  }
  Start-Process -WindowStyle Hidden -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $HOME\.pluribusai\poll-windows.ps1"
}

Say "Control plane: http://localhost:8080"
Say "Data plane:    http://localhost:30787"
Say "Dashboard:     http://localhost:8080/auth/dev-login?as=ricardo"
Say "Run test-all.ps1 when ready."