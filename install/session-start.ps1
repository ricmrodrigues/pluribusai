$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
$envFile = Join-Path $dir 'env.ps1'
if (-not (Test-Path $envFile)) { exit 0 }
. $envFile

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }
if ($PLURIBUSAI_USER)   { $headers['X-PluribusAI-User'] = $PLURIBUSAI_USER }

$inboxBody = @{
  jsonrpc = '2.0'; id = 1; method = 'tools/call'
  params = @{ name = 'get_inbox'; arguments = @{} }
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

$threadBody = @{
  jsonrpc = '2.0'; id = 2; method = 'tools/call'
  params = @{
    name = 'get_thread_updates'
    arguments = @{ limit = 5 }
  }
} | ConvertTo-Json -Depth 6 -Compress
try {
  $thr = Invoke-RestMethod -Uri "$PLURIBUSAI_ENDPOINT/mcp" -Method Post `
    -Body $threadBody -Headers $headers -TimeoutSec 8
  $threads = ($thr.result.content[0].text | ConvertFrom-Json).threads
  foreach ($t in ($threads | Select-Object -Last 5)) {
    $lr = $t.latest_reply
    Write-Output "  - [reply] $($lr.author) on $($t.message_id): $($lr.preview)"
  }
} catch {}

Write-Output 'Use PluribusAI MCP tools (get_inbox, get_activity, read_message, reply_message) for team collaboration.'