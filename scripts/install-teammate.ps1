# One-shot Windows teammate install (Cursor MCP + poll daemon + toasts).
param(
  [Parameter(Mandatory)][string]$User,
  [Parameter(Mandatory)][string]$Token,
  [string]$Endpoint = "http://192.168.1.116:30787",
  [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
  $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$Dir = "$HOME\.pluribusai"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = "python" }

@(
  "`$PLURIBUSAI_TOKEN    = '$Token'"
  "`$PLURIBUSAI_ENDPOINT = '$Endpoint'"
  "`$PLURIBUSAI_USER     = '$User'"
  "`$PLURIBUSAI_PYTHON   = '$py'"
  "`$PLURIBUSAI_FOCUS_APP = 'cursor,grok'"
) | Set-Content "$Dir\env.ps1" -Encoding UTF8

Copy-Item "$RepoRoot\install\poll-windows.ps1" "$Dir\" -Force
Copy-Item "$RepoRoot\install\toast-windows.ps1" "$Dir\" -Force
Copy-Item "$RepoRoot\install\winrt-toast.ps1" "$Dir\" -Force
Copy-Item "$RepoRoot\install\click-handler.py" "$Dir\" -Force
Copy-Item "$RepoRoot\install\protocol-open.ps1" "$Dir\" -Force
Copy-Item "$RepoRoot\install\register-windows-toast.ps1" "$Dir\" -Force
Copy-Item "$RepoRoot\install\poll-hidden.vbs" "$Dir\" -Force

python "$RepoRoot\install\cursor_util.py" install $Endpoint $Token $User

# Restart poll daemon
if (Test-Path "$Dir\poll.pid") {
  $old = Get-Content "$Dir\poll.pid" -ErrorAction SilentlyContinue
  if ($old) { Stop-Process -Id $old -Force -ErrorAction SilentlyContinue }
}
Start-Process -WindowStyle Hidden -FilePath "powershell.exe" `
  -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Dir\poll-windows.ps1`""

Write-Host "Installed for $User -> $Endpoint"
Write-Host "Restart Cursor to pick up MCP config."