# Build image and helm install pluribusai (Docker Desktop Kubernetes or any cluster).
# Usage:  .\scripts\helm-install.ps1 [-Namespace pluribusai] [-Store sqlite|postgres]
param(
  [string]$Namespace = "pluribusai",
  [ValidateSet("sqlite", "postgres")]
  [string]$Store = "sqlite",
  [string]$Token = "",
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Chart = Join-Path $Root "deploy\helm\pluribusai"

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$helm = Get-Command helm -ErrorAction SilentlyContinue
if (-not $helm) {
  Write-Error "helm not found. Install: winget install Helm.Helm"
}

if ($Uninstall) {
  Say "Uninstalling pluribusai from $Namespace..."
  helm uninstall pluribusai -n $Namespace 2>$null
  kubectl delete namespace $Namespace 2>$null
  exit 0
}

$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectl) {
  Write-Error "kubectl not found. Install Docker Desktop (Kubernetes) or: winget install Kubernetes.kubectl"
}

Say "Building pluribusai:0.6.0 image..."
docker build -t pluribusai:0.6.0 $Root

if (-not $Token) {
  $Token = -join ((48..57) + (97..102) | Get-Random -Count 48 | ForEach-Object { [char]$_ })
  # simpler token:
  $Token = "pk_" + ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")).Substring(0, 32)
}

Say "Installing helm release (store=$Store)..."
$setArgs = @(
  "upgrade", "--install", "pluribusai", $Chart,
  "--namespace", $Namespace, "--create-namespace",
  "--set", "store.type=$Store",
  "--set", "image.pullPolicy=Never",
  "--set", "auth.token=$Token",
  "--wait", "--timeout", "5m"
)
helm @setArgs

Say "Waiting for pod..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=pluribusai `
  -n $Namespace --timeout=120s

Say "Token (save for client install): $Token"
Say "Port-forward: kubectl port-forward svc/pluribusai 8787:8787 -n $Namespace"
Say "Health:       curl http://localhost:8787/health"
Say "Helm test:    helm test pluribusai -n $Namespace"