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
CURSOR_CFG=$(python "$SCRIPT_DIR/cursor_util.py" install "$ENDPOINT" "$TOKEN" "$USER_ID")
say "  cursor -> $CURSOR_CFG"

PY_WIN=$(python -c "import sys; print(sys.executable.replace(chr(92), chr(92)*2))" 2>/dev/null || echo python)
cat > "$DIR/env.ps1" <<EOF
\$PLURIBUSAI_TOKEN    = '$TOKEN'
\$PLURIBUSAI_ENDPOINT = '$ENDPOINT'
\$PLURIBUSAI_USER     = '$USER_ID'
\$PLURIBUSAI_PYTHON   = '$PY_WIN'
EOF

cp "$SCRIPT_DIR/session-start.ps1" "$DIR/session-start.ps1"

cp "$SCRIPT_DIR/poll-windows.ps1" "$DIR/poll.ps1"
cp "$SCRIPT_DIR/winrt-toast.ps1" "$DIR/winrt-toast.ps1"
cp "$SCRIPT_DIR/protocol-open.ps1" "$DIR/protocol-open.ps1"
cp "$SCRIPT_DIR/register-windows-toast.ps1" "$DIR/register-windows-toast.ps1"
cp "$SCRIPT_DIR/click-handler.py" "$DIR/click-handler.py"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$DIR/register-windows-toast.ps1" >/dev/null 2>&1 || true

cp "$SCRIPT_DIR/poll-hidden.vbs" "$DIR/poll-hidden.vbs"
VBS_WIN=$(cygpath -w "$DIR/poll-hidden.vbs")
schtasks //Delete //TN "$TASK" //F 2>/dev/null || true

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

say "Starting continuous poll daemon (long-poll, near-real-time toasts)..."
schtasks //Create //TN "$TASK" //SC ONLOGON //F //TR "wscript.exe \"$VBS_WIN\"" >/dev/null
wscript.exe "$VBS_WIN" >/dev/null 2>&1 &

echo "0" > "$DIR/.activity-cursor"

echo
say "Done. Endpoint: $ENDPOINT/mcp"
if [ "$HAS_CLAUDE" -eq 1 ]; then
  echo "   • Restart Claude Code for MCP + status line"
fi
echo "   • Restart Cursor (or reload MCP) for ~/.cursor/mcp.json"