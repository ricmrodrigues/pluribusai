# Full-stack smoke tests — run at the end to verify everything.
param(
  [string]$ControlPlane = "http://127.0.0.1:8080",
  [string]$DataPlane = "http://localhost:30787",
  [string]$LanIp = ""
)

$ErrorActionPreference = "Continue"
$script:failed = @()
$script:passed = 0

function Check($name, $cond) {
  if ($cond) {
    Write-Host "PASS $name" -ForegroundColor Green
    $script:passed++
  } else {
    Write-Host "FAIL $name" -ForegroundColor Red
    $script:failed += $name
  }
}

function DevToken($user) {
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $null = Invoke-WebRequest -Uri "$ControlPlane/auth/dev-login?as=$user" -WebSession $s -UseBasicParsing
  (Invoke-RestMethod -Uri "$ControlPlane/api/token" -WebSession $s)
}

Write-Host "`n=== PluribusAI full stack test ===`n" -ForegroundColor Cyan

# 1. Control plane
try {
  $cp = Invoke-RestMethod -Uri "$ControlPlane/health" -TimeoutSec 5
  Check "control plane health" ($cp.status -eq "ok")
} catch { Check "control plane health" $false }

# 2. Data plane
try {
  $dp = Invoke-RestMethod -Uri "$DataPlane/health" -TimeoutSec 5
  Check "data plane health" ($dp.status -eq "ok")
  Check "data plane jwt on" ($dp.jwt -eq "on")
  Check "data plane v0.6" ($dp.version -eq "0.6.0")
} catch { Check "data plane health" $false }

# 3. Ricardo JWT -> MCP
try {
  $ric = DevToken "ricardo"
  $body = @{
    jsonrpc = "2.0"; id = 1; method = "tools/call"
    params = @{
      name = "send_message"
      arguments = @{
        sender = $ric.username; audience = "all"
        content = "TEST-ALL ricardo $(Get-Date -Format o)"
      }
    }
  } | ConvertTo-Json -Depth 6
  $h = @{
    Authorization = "Bearer $($ric.access_token)"
    "X-PluribusAI-User" = $ric.username
    "Content-Type" = "application/json"
  }
  $mcp = Invoke-RestMethod -Uri "$DataPlane/mcp" -Method Post -Headers $h -Body $body
  Check "ricardo mcp send" ($mcp.result.content.Count -ge 1)
} catch { Check "ricardo mcp send" $false }

# 4. Ana JWT -> MCP
try {
  $ana = DevToken "ana"
  $body = @{
    jsonrpc = "2.0"; id = 2; method = "tools/call"
    params = @{
      name = "send_message"
      arguments = @{
        sender = $ana.username; audience = @("ricardo")
        content = "TEST-ALL ana DM $(Get-Date -Format o)"
      }
    }
  } | ConvertTo-Json -Depth 6
  $h = @{
    Authorization = "Bearer $($ana.access_token)"
    "X-PluribusAI-User" = $ana.username
    "Content-Type" = "application/json"
  }
  $mcp = Invoke-RestMethod -Uri "$DataPlane/mcp" -Method Post -Headers $h -Body $body
  Check "ana mcp send" ($mcp.result.content.Count -ge 1)
} catch { Check "ana mcp send" $false }

# 5. Ricardo inbox sees ana message
try {
  $ric = DevToken "ricardo"
  $body = @{
    jsonrpc = "2.0"; id = 3; method = "tools/call"
    params = @{ name = "get_inbox"; arguments = @{ user = "ricardo" } }
  } | ConvertTo-Json -Depth 5
  $h = @{
    Authorization = "Bearer $($ric.access_token)"
    "X-PluribusAI-User" = "ricardo"
    "Content-Type" = "application/json"
  }
  $mcp = Invoke-RestMethod -Uri "$DataPlane/mcp" -Method Post -Headers $h -Body $body
  $txt = $mcp.result.content[0].text
  Check "ricardo inbox" ($txt -match "unread|message")
} catch { Check "ricardo inbox" $false }

# 6. Admin teammate token API
try {
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $null = Invoke-WebRequest -Uri "$ControlPlane/auth/dev-login?as=ricardo" -WebSession $s -UseBasicParsing
  $t = Invoke-RestMethod -Uri "$ControlPlane/api/teammate-token/ana" -WebSession $s
  Check "admin teammate-token" ($t.access_token.Length -gt 20)
} catch { Check "admin teammate-token" $false }

# 7. Activity long-poll
try {
  $ric = DevToken "ricardo"
  $uri = "$DataPlane/activity?user=ricardo&since=0&timeout=2&limit=5"
  $h = @{ Authorization = "Bearer $($ric.access_token)" }
  $act = Invoke-RestMethod -Uri $uri -Headers $h -TimeoutSec 8
  Check "activity endpoint" ($null -ne $act.events)
} catch { Check "activity endpoint" $false }

# 8. LAN reachability hint
if (-not $LanIp) {
  $LanIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -like "192.168.1.*" } |
    Select-Object -First 1).IPAddress
  if (-not $LanIp) {
    $LanIp = (Get-NetIPAddress -AddressFamily IPv4 |
      Where-Object { $_.IPAddress -like "192.168.*" } |
      Select-Object -First 1).IPAddress
  }
}
if ($LanIp) {
  try {
    $lan = Invoke-RestMethod -Uri "http://${LanIp}:30787/health" -TimeoutSec 3
    Check "LAN health ($LanIp)" ($lan.status -eq "ok")
  } catch { Check "LAN health ($LanIp)" $false }
}

# 9. Cursor MCP config
$mcpPath = "$HOME\.cursor\mcp.json"
if (Test-Path $mcpPath) {
  $cfg = Get-Content $mcpPath -Raw | ConvertFrom-Json
  $entry = $cfg.mcpServers.pluribusai
  Check "cursor mcp configured" ($entry.url -match "30787|8787")
  Check "cursor mcp has auth" ($entry.headers.Authorization -match "Bearer")
} else {
  Check "cursor mcp configured" $false
}

# 10. Poll daemon
if (Test-Path "$HOME\.pluribusai\poll.pid") {
  $pollPid = Get-Content "$HOME\.pluribusai\poll.pid"
  $alive = Get-Process -Id $pollPid -ErrorAction SilentlyContinue
  Check "poll daemon running" ($null -ne $alive)
} else {
  Check "poll daemon running" $false
}

Write-Host "`n=== $($script:passed) passed, $($script:failed.Count) failed ===" -ForegroundColor $(if ($script:failed.Count -eq 0) { "Green" } else { "Yellow" })
if ($script:failed.Count -gt 0) {
  Write-Host "Failed: $($script:failed -join ', ')"
  exit 1
}
exit 0