# Sync ~/.cursor/mcp.json from ~/.pluribusai/env.ps1
param(
  [string]$EnvFile = (Join-Path $HOME ".pluribusai\env.ps1")
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $EnvFile)) {
  Write-Error "Missing $EnvFile - run wire-client.ps1 first"
}
. $EnvFile
$Root = Split-Path $PSScriptRoot -Parent
& python (Join-Path $Root "install\cursor_util.py") install `
  "$PLURIBUSAI_ENDPOINT" "$PLURIBUSAI_TOKEN" "$PLURIBUSAI_USER"
Write-Host ("Cursor MCP updated: " + (Join-Path $HOME ".cursor\mcp.json"))