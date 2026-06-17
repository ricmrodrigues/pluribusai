#!/usr/bin/env bash
# PluribusAI installer for Windows (run once in Git Bash).
#
# Usage:
#   PLURIBUSAI_ENDPOINT=http://localhost:8787 PLURIBUSAI_TOKEN=xxx PLURIBUSAI_USER=you ./install-windows.sh
#   ./install-windows.sh --uninstall
#
# Configures Cursor MCP automatically. Claude Code extras (status line, SessionStart)
# install when the `claude` CLI is available.

set -e

ENDPOINT="${PLURIBUSAI_ENDPOINT:-http://localhost:8787}"
ENDPOINT="${ENDPOINT%/}"
DIR="$HOME/.pluribusai"
SETTINGS="$HOME/.claude/settings.json"
TASK="pluribusai-poll"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\033[36m==>\033[0m %s\n' "$1"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

if [ "$1" = "--uninstall" ]; then
  say "Uninstalling PluribusAI..."
  schtasks //Delete //TN "$TASK" //F 2>/dev/null || true
  rm -rf "$DIR"
  claude mcp remove --scope user pluribusai 2>/dev/null || true
  claude mcp remove --scope user team-mcp 2>/dev/null || true
  if command -v python >/dev/null 2>&1; then
    python - "$SETTINGS" <<'PY' 2>/dev/null || true
import json,sys
p=sys.argv[1]
try: d=json.load(open(p))
except Exception: d={}
d.pop("statusLine",None)
json.dump(d,open(p,"w"),indent=2)
PY
    python "$SCRIPT_DIR/hooks_util.py" uninstall "$SETTINGS" 2>/dev/null || true
    python "$SCRIPT_DIR/cursor_util.py" uninstall 2>/dev/null || true
  fi
  say "Removed."
  exit 0
fi

command -v schtasks >/dev/null 2>&1 || die "schtasks not found."
command -v powershell >/dev/null 2>&1 || command -v powershell.exe >/dev/null 2>&1 || die "powershell not found."
command -v python >/dev/null 2>&1 || die "python not found (needed for Cursor MCP config)."

HAS_CLAUDE=0
command -v claude >/dev/null 2>&1 && HAS_CLAUDE=1

TOKEN="${PLURIBUSAI_TOKEN:-}"
if [ -z "$TOKEN" ]; then printf "Enter PluribusAI token (empty if none): "; read -r TOKEN; fi
USER_ID="${PLURIBUSAI_USER:-}"
if [ -z "$USER_ID" ]; then printf "Enter username: "; read -r USER_ID; fi
[ -n "$USER_ID" ] || die "No username."

mkdir -p "$DIR"
DIR_WIN=$(cygpath -w "$DIR")

if [ "$HAS_CLAUDE" -eq 1 ]; then
  say "Registering PluribusAI with Claude Code..."
  claude mcp remove --scope user pluribusai >/dev/null 2>&1 || true
  claude mcp remove --scope user team-mcp >/dev/null 2>&1 || true
  if [ -n "$TOKEN" ]; then
    claude mcp add --scope user --transport http pluribusai "$ENDPOINT/mcp" \
      --header "Authorization: Bearer $TOKEN" >/dev/null
  else
    claude mcp add --scope user --transport http pluribusai "$ENDPOINT/mcp" >/dev/null
  fi
else
  say "Claude CLI not found — skipping Claude MCP (Cursor will still be configured)."
fi

say "Registering PluribusAI with Cursor..."
CURSOR_CFG=$(python "$SCRIPT_DIR/cursor_util.py" install "$ENDPOINT" "$TOKEN")
say "  cursor -> $CURSOR_CFG"

cat > "$DIR/env.ps1" <<EOF
\$PLURIBUSAI_TOKEN    = '$TOKEN'
\$PLURIBUSAI_ENDPOINT = '$ENDPOINT'
\$PLURIBUSAI_USER     = '$USER_ID'
EOF

cp "$SCRIPT_DIR/session-start.ps1" "$DIR/session-start.ps1"

cat > "$DIR/poll.ps1" <<'PS1'
$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path $env:USERPROFILE '.pluribusai'
. (Join-Path $dir 'env.ps1')
$cache   = Join-Path $dir 'open-count.txt'
$cursorF = Join-Path $dir '.activity-cursor'
$slfile  = Join-Path $dir 'statusline.txt'

$headers = @{ 'Content-Type' = 'application/json' }
if ($PLURIBUSAI_TOKEN) { $headers['Authorization'] = "Bearer $PLURIBUSAI_TOKEN" }

function Show-Toast($text) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.Visible = $true
    $n.ShowBalloonTip(5000, 'PluribusAI', $text, 'Info')
    Start-Sleep -Seconds 6
    $n.Dispose()
  } catch {}
}

$cursor = 0.0
if (Test-Path $cursorF) { $cursor = [double](Get-Content $cursorF) }
$actUri = "$PLURIBUSAI_ENDPOINT/activity?user=$PLURIBUSAI_USER&since=$cursor&timeout=55&limit=50"
try {
  $act = Invoke-RestMethod -Uri $actUri -Method Get -Headers $headers -TimeoutSec 65
  foreach ($e in $act.events) {
    if ($e.type -eq 'reply') { Show-Toast "$($e.author) replied on $($e.message_id)" }
    else { Show-Toast "New message from $($e.sender)" }
  }
  if ($act.count -gt 0) {
    [System.IO.File]::WriteAllText($cursorF, "$($act.cursor)")
  }
} catch {}

$body = @{ jsonrpc='2.0'; id=1; method='tools/call'; params=@{
  name='get_inbox'; arguments=@{ user=$PLURIBUSAI_USER } } } | ConvertTo-Json -Depth 6
try {
  $resp = Invoke-RestMethod -Uri "$PLURIBUSAI_ENDPOINT/mcp" -Method Post -Body $body `
    -Headers $headers -TimeoutSec 8
  $count = [int](($resp.result.content[0].text | ConvertFrom-Json).count)
  [System.IO.File]::WriteAllText($cache, "$count")
  if ($count -eq 0) { $txt = 'pluribusai: clear' }
  else { $txt = "pluribusai: $count new" }
} catch {
  [System.IO.File]::WriteAllText($cache, '?')
  $txt = 'pluribusai: ?'
}
[System.IO.File]::WriteAllText($slfile, $txt, (New-Object System.Text.UTF8Encoding $false))
PS1

cat > "$DIR/poll-hidden.vbs" <<'VBS'
Set sh = CreateObject("WScript.Shell")
ps1 = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.pluribusai\poll.ps1"
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False
VBS
VBS_WIN=$(cygpath -w "$DIR/poll-hidden.vbs")

if [ "$HAS_CLAUDE" -eq 1 ]; then
  say "Configuring Claude statusLine + SessionStart hook..."
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  SL_FILE_WIN="$DIR_WIN\\statusline.txt"
  SS_FILE_WIN="$DIR_WIN\\session-start.ps1"
  SL_CMD="cmd /c type \"$SL_FILE_WIN\""
  export SL_CMD
  python - "$SETTINGS" <<'PY'
import json,os,sys
p=sys.argv[1]
try: d=json.load(open(p))
except Exception: d={}
d["statusLine"]={"type":"command","command":os.environ["SL_CMD"]}
json.dump(d,open(p,"w"),indent=2)
PY
  SS_CMD="powershell -NoProfile -ExecutionPolicy Bypass -File \"$SS_FILE_WIN\""
  python "$SCRIPT_DIR/hooks_util.py" install "$SETTINGS" "$SS_CMD"
fi

say "Creating scheduled task '$TASK' (desktop notifications)..."
schtasks //Create //TN "$TASK" //SC MINUTE //MO 1 //F //TR "wscript.exe \"$VBS_WIN\"" >/dev/null

PS1_WIN=$(cygpath -w "$DIR/poll.ps1")
echo "0" > "$DIR/.activity-cursor"
powershell -NoProfile -ExecutionPolicy Bypass -File "$PS1_WIN" >/dev/null 2>&1 || true

echo
say "Done. Endpoint: $ENDPOINT/mcp"
if [ "$HAS_CLAUDE" -eq 1 ]; then
  echo "   • Restart Claude Code for MCP + status line"
fi
echo "   • Restart Cursor (or reload MCP) for ~/.cursor/mcp.json"