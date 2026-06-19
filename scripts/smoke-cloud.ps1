# End-to-end: control plane JWT -> k8s data plane MCP
param(
  [string]$User = "ricardo",
  [string]$ControlPlane = "http://127.0.0.1:8080",
  [string]$DataPlane = "http://localhost:30787"
)

$ErrorActionPreference = "Stop"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$ControlPlane/auth/dev-login?as=$User" -WebSession $session -UseBasicParsing
$tok = Invoke-RestMethod -Uri "$ControlPlane/api/token" -WebSession $session
$jwt = $tok.access_token
$user = $tok.username
Write-Host "JWT user: $user"

$body = @{
  jsonrpc = "2.0"
  id = 1
  method = "tools/call"
  params = @{
    name = "send_message"
    arguments = @{
      sender = $user
      audience = "all"
      content = "CLOUD WIRE TEST - JWT from control plane to k8s"
    }
  }
} | ConvertTo-Json -Depth 6

$headers = @{
  Authorization = "Bearer $jwt"
  "X-PluribusAI-User" = $user
  "Content-Type" = "application/json"
}
$r = Invoke-RestMethod -Uri "$DataPlane/mcp" -Method Post -Headers $headers -Body $body
Write-Host "MCP result:" ($r | ConvertTo-Json -Depth 4 -Compress)

$h = Invoke-RestMethod -Uri "$DataPlane/health" -Headers @{ Authorization = "Bearer $jwt" }
Write-Host "Health:" ($h | ConvertTo-Json -Compress)