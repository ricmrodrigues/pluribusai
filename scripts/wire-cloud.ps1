# Wire k8s data plane to local control plane (JWT + pk_* validation).
param(
  [string]$Namespace = "pluribusai",
  [string]$JwtSecret = "pluribusai-cloud-jwt-secret-change-me-32ch",
  [string]$ControlPlaneUrl = "http://host.docker.internal:8080",
  [int]$NodePort = 30787,
  [string]$ExistingToken = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Chart = Join-Path $Root "deploy\helm\pluribusai"

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

if (-not $ExistingToken) {
  $ExistingToken = kubectl get secret pluribusai -n $Namespace `
    -o jsonpath='{.data.PLURIBUSAI_TOKEN}' 2>$null
  if ($ExistingToken) {
    $ExistingToken = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ExistingToken))
  }
}
if (-not $ExistingToken) {
  $ExistingToken = "pk_" + ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")).Substring(0, 32)
}

Say "Rebuilding pluribusai:0.6.0 (PyJWT for control-plane auth)..."
docker build -t pluribusai:0.6.0 $Root

Say "Helm upgrade with JWT + control-plane URL..."
helm upgrade pluribusai $Chart -n $Namespace `
  --reuse-values `
  --set image.pullPolicy=Never `
  --set auth.token=$ExistingToken `
  --set auth.jwtSecret=$JwtSecret `
  --set auth.jwtIssuer=pluribusai-control `
  --set auth.controlPlaneUrl=$ControlPlaneUrl `
  --set auth.internalSecret=$JwtSecret `
  --set service.type=NodePort `
  --set service.nodePort=$NodePort `
  --wait --timeout 5m

kubectl rollout restart deployment/pluribusai -n $Namespace
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=pluribusai `
  -n $Namespace --timeout=120s

Say "Control plane env (match JwtSecret):"
Write-Host "  CONTROL_PLANE_SECRET=$JwtSecret"
Write-Host "  DATA_PLANE_URL=http://localhost:${NodePort}"
Write-Host "  PLURIBUSAI_INTERNAL_SECRET=$JwtSecret"
Say "Data plane token (legacy): $ExistingToken"
Say "Health: curl http://localhost:${NodePort}/health"