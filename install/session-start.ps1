$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
$envFile = Join-Path $dir 'env.ps1'
if (-not (Test-Path $envFile)) { exit 0 }
. $envFile

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }

$inboxBody = @{
  jsonrpc = '2.0'; id = 1; method = 'tools/call'
  params = @{ name = 'get_inbox'; arguments = @{ user = $PLURIBUSAI_USER } }
} | ConvertTo-Json -Depth 6 -Compress

try {
  $resp = Invoke-RestMethod -Uri "$PLURIBUSAI_ENDPOINT/mcp" -Method Post `
    -Body $inboxBody -Headers $headers -TimeoutSec 8
  $count = [int](($resp.result.content[0].text | ConvertFrom-Json).count)
} catch {
  Write-Output "PluribusAI: endpoint unreachable ($PLURIBUSAI_ENDPOINT)."
  exit 0
}

Write-Output "PluribusAI inbox for ${PLURIBUSAI_USER}: $count unread message(s)."

if ($count -gt 0) {
  $actBody = @{
    jsonrpc = '2.0'; id = 2; method = 'tools/call'
    params = @{
      name = 'get_activity'
      arguments = @{ user = $PLURIBUSAI_USER; since = 0; limit = 5 }
    }
  } | ConvertTo-Json -Depth 6 -Compress
  try {
    $act = Invoke-RestMethod -Uri "$PLURIBUSAI_ENDPOINT/mcp" -Method Post `
      -Body $actBody -Headers $headers -TimeoutSec 8
    $events = ($act.result.content[0].text | ConvertFrom-Json).events
    foreach ($e in $events | Select-Object -Last 5) {
      if ($e.type -eq 'message') {
        Write-Output "  - [new] $($e.sender): $($e.preview) ($($e.message_id))"
      } else {
        Write-Output "  - [reply] $($e.author) on $($e.message_id): $($e.preview)"
      }
    }
  } catch {}
}

Write-Output 'Use PluribusAI MCP tools (get_inbox, get_activity, read_message, reply_message) for team collaboration.'