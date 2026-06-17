#!/bin/sh
# Background poller: long-poll /activity + macOS notifications (osascript).
. "$HOME/.pluribusai/env"
DIR="$HOME/.pluribusai"
CACHE="$DIR/open-count.txt"
CURSOR="$DIR/.activity-cursor"
USER_HDR=""
[ -n "$PLURIBUSAI_USER" ] && USER_HDR="-H X-PluribusAI-User: $PLURIBUSAI_USER"

refresh_inbox() {
  req='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_inbox","arguments":{}}}'
  if [ -n "$PLURIBUSAI_TOKEN" ]; then
    count=$(curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
      -H 'Content-Type: application/json' -H "Authorization: Bearer $PLURIBUSAI_TOKEN" \
      $USER_HDR -d "$req" 2>/dev/null \
      | python3 -c "import sys,json;print(json.loads(json.load(sys.stdin)['result']['content'][0]['text'])['count'])" 2>/dev/null)
  else
    count=$(curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
      -H 'Content-Type: application/json' $USER_HDR -d "$req" 2>/dev/null \
      | python3 -c "import sys,json;print(json.loads(json.load(sys.stdin)['result']['content'][0]['text'])['count'])" 2>/dev/null)
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