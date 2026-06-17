#!/bin/sh
# PluribusAI installer — MCP registration + ambient notifications (macOS).
#
# Usage:
#   ./install.sh
#   PLURIBUSAI_ENDPOINT=http://localhost:8787 PLURIBUSAI_TOKEN=xxx PLURIBUSAI_USER=you ./install.sh
#   ./install.sh --uninstall
#
# Requires: macOS, Claude Code CLI, python3, curl.

set -e

ENDPOINT="${PLURIBUSAI_ENDPOINT:-http://localhost:8787}"
ENDPOINT="${ENDPOINT%/}"
DIR="$HOME/.pluribusai"
PLIST="$HOME/Library/LaunchAgents/com.pluribusai.poll.plist"
LABEL="com.pluribusai.poll"
SETTINGS="$HOME/.claude/settings.json"
REFRESH_SECS="${PLURIBUSAI_REFRESH:-${REFRESH_SECS:-60}}"

say() { printf '\033[36m==>\033[0m %s\n' "$1"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

if [ "$1" = "--uninstall" ]; then
  say "Uninstalling PluribusAI client widgets..."
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$DIR"
  claude mcp remove --scope user pluribusai 2>/dev/null || true
  claude mcp remove --scope user team-mcp 2>/dev/null || true
  python3 - "$SETTINGS" <<'PY' 2>/dev/null || true
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d.pop("statusLine",None)
json.dump(d,open(p,"w"),indent=2)
PY
  python3 "$(dirname "$0")/hooks_util.py" uninstall "$SETTINGS" 2>/dev/null || true
  python3 "$(dirname "$0")/cursor_util.py" uninstall 2>/dev/null || true
  say "Removed."
  exit 0
fi

command -v claude  >/dev/null 2>&1 || die "Claude Code CLI 'claude' not found in PATH."
command -v python3 >/dev/null 2>&1 || die "python3 not found."
command -v curl    >/dev/null 2>&1 || die "curl not found."

TOKEN="${PLURIBUSAI_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  printf "Enter PluribusAI bearer token (empty if auth disabled): "
  read -r TOKEN
fi

USER_ID="${PLURIBUSAI_USER:-}"
if [ -z "$USER_ID" ]; then
  printf "Enter your username (e.g. first name, lowercase): "
  read -r USER_ID
fi
[ -n "$USER_ID" ] || die "No username provided."

mkdir -p "$DIR" "$HOME/Library/LaunchAgents"

say "Registering PluribusAI with Claude Code..."
claude mcp remove --scope user pluribusai >/dev/null 2>&1 || true
claude mcp remove --scope user team-mcp >/dev/null 2>&1 || true
if [ -n "$TOKEN" ]; then
  claude mcp add --scope user --transport http pluribusai "$ENDPOINT/mcp" \
    --header "Authorization: Bearer $TOKEN" >/dev/null
else
  claude mcp add --scope user --transport http pluribusai "$ENDPOINT/mcp" >/dev/null
fi
say "  registered -> $ENDPOINT/mcp"

say "Registering PluribusAI with Cursor..."
CURSOR_CFG=$(python3 "$(dirname "$0")/cursor_util.py" install "$ENDPOINT" "$TOKEN")
say "  cursor -> $CURSOR_CFG"

say "Writing poller + statusline to $DIR ..."
cat > "$DIR/env" <<EOF
PLURIBUSAI_TOKEN="$TOKEN"
PLURIBUSAI_ENDPOINT="$ENDPOINT"
PLURIBUSAI_USER="$USER_ID"
PLURIBUSAI_REFRESH="$REFRESH_SECS"
EOF
chmod 600 "$DIR/env"

cat > "$DIR/poll.sh" <<'EOF'
#!/bin/sh
. "$HOME/.pluribusai/env"
DIR="$HOME/.pluribusai"
CACHE="$DIR/open-count.txt"
CURSOR="$DIR/.activity-cursor"
notify() { osascript -e "display notification \"$1\" with title \"PluribusAI\" sound name \"Glass\"" 2>/dev/null; }
refresh_inbox() {
  req="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_inbox\",\"arguments\":{\"user\":\"$PLURIBUSAI_USER\"}}}"
  if [ -n "$PLURIBUSAI_TOKEN" ]; then
    count=$(curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
      -H 'Content-Type: application/json' -H "Authorization: Bearer $PLURIBUSAI_TOKEN" \
      -d "$req" 2>/dev/null | python3 -c "import sys,json;print(json.loads(json.load(sys.stdin)['result']['content'][0]['text'])['count'])" 2>/dev/null)
  else
    count=$(curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
      -H 'Content-Type: application/json' \
      -d "$req" 2>/dev/null | python3 -c "import sys,json;print(json.loads(json.load(sys.stdin)['result']['content'][0]['text'])['count'])" 2>/dev/null)
  fi
  if [ -n "$count" ]; then echo "$count" > "$CACHE"; else echo "?" > "$CACHE"; fi
}
while :; do
  cursor=$(cat "$CURSOR" 2>/dev/null || echo 0)
  url="$PLURIBUSAI_ENDPOINT/activity?user=$PLURIBUSAI_USER&since=$cursor&timeout=55&limit=50"
  if [ -n "$PLURIBUSAI_TOKEN" ]; then
    body=$(curl -s --max-time 65 -G "$url" -H "Authorization: Bearer $PLURIBUSAI_TOKEN")
  else
    body=$(curl -s --max-time 65 -G "$url")
  fi
  python3 - "$body" "$CURSOR" <<'PY'
import json, sys, subprocess
body, cursor_path = sys.argv[1], sys.argv[2]
try:
    data = json.loads(body or "{}")
except Exception:
    data = {"events": [], "count": 0, "cursor": 0}
events = data.get("events") or []
if events:
    for e in events:
        if e.get("type") == "reply":
            msg = f"{e.get('author')} replied on {e.get('message_id')}"
        else:
            msg = f"New message from {e.get('sender')}"
        subprocess.run(["osascript", "-e",
            f'display notification "{msg}" with title "PluribusAI" sound name "Glass"'],
            check=False)
    open(cursor_path, "w").write(str(data.get("cursor", 0)))
PY
  refresh_inbox
done
EOF
chmod +x "$DIR/poll.sh"
cp "$(dirname "$0")/session-start.sh" "$DIR/session-start.sh"
chmod +x "$DIR/session-start.sh"

cat > "$DIR/statusline.sh" <<'EOF'
#!/bin/sh
cat >/dev/null 2>&1
CACHE="$HOME/.pluribusai/open-count.txt"
[ -f "$CACHE" ] || { printf '\033[90m⬡ pluribusai: --\033[0m'; exit 0; }
count=$(cat "$CACHE" 2>/dev/null)
now=$(date +%s); mtime=$(stat -f %m "$CACHE" 2>/dev/null || echo "$now"); age=$((now-mtime))
if [ "$age" -gt 180 ]; then printf '\033[90m⬡ pluribusai: stale\033[0m'
elif [ "$count" = "0" ]; then printf '\033[90m⬡ pluribusai: clear\033[0m'
elif [ "$count" = "?" ]; then printf '\033[90m⬡ pluribusai: ?\033[0m'
else printf '\033[33m⬡ pluribusai: %s new\033[0m' "$count"; fi
EOF
chmod +x "$DIR/statusline.sh"

say "Configuring Claude statusLine + SessionStart hook..."
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
python3 - "$SETTINGS" <<'PY'
import json,sys
p=sys.argv[1]
try: d=json.load(open(p))
except Exception: d={}
d["statusLine"]={"type":"command","command":"sh ~/.pluribusai/statusline.sh"}
json.dump(d,open(p,"w"),indent=2)
PY
python3 "$(dirname "$0")/hooks_util.py" install "$SETTINGS" "sh $DIR/session-start.sh"

say "Installing launchd poller ($LABEL)..."
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$DIR/poll.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$DIR/poll.err</string>
  <key>StandardOutPath</key><string>$DIR/poll.out</string>
</dict></plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

say "Priming inbox cache..."
req="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_inbox\",\"arguments\":{\"user\":\"$USER_ID\"}}}"
auth=()
[ -n "$TOKEN" ] && auth=(-H "Authorization: Bearer $TOKEN")
c=$(curl -s --max-time 10 -X POST "$ENDPOINT/mcp" -H 'Content-Type: application/json' \
  "${auth[@]}" -d "$req" 2>/dev/null \
  | python3 -c "import sys,json;print(json.loads(json.load(sys.stdin)['result']['content'][0]['text'])['count'])" 2>/dev/null) || true
echo "${c:-?}" > "$DIR/open-count.txt"
echo "0" > "$DIR/.activity-cursor"

echo
if [ -n "$c" ]; then
  say "Success — $USER_ID has $c unread message(s) at $ENDPOINT"
else
  printf '\033[33m==>\033[0m Installed; endpoint not reachable yet (status line shows stale).\n'
fi
echo "   • Restart Claude and/or Cursor to pick up the MCP server"
echo "   • Uninstall: ./install.sh --uninstall"