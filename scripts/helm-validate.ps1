# Validate Helm chart (lint + template renders) — no cluster required.
$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Chart = Join-Path $Root "deploy\helm\pluribusai"

helm lint $Chart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = (helm template pluribusai $Chart --set auth.token=lint-token 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($out -notlike "*kind: Deployment*") { throw "missing Deployment" }
if ($out -notlike "*PLURIBUSAI_STORE*") { throw "missing store env" }
if ($out -like "*pluribusai-postgresql*") { throw "sqlite default must not render postgres" }

$outPg = (helm template pluribusai $Chart --set store.type=postgres --set auth.token=t 2>&1 | Out-String)
if ($outPg -notlike "*pluribusai-postgresql*") { throw "postgres mode must render bundled postgres" }

Write-Host "helm chart validation passed" -ForegroundColor Green