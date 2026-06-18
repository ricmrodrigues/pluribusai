#!/bin/sh
# Background poller: long-poll /activity + macOS notifications (clickable via terminal-notifier).
. "$HOME/.pluribusai/env"
DIR="$HOME/.pluribusai"
CACHE="$DIR/open-count.txt"
CURSOR="$DIR/.activity-cursor"
CLICK="$DIR/click-handler.py"
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
  python3 - "$body" "$CURSOR" "$CLICK" <<'PY'
import json, shlex, subprocess, sys

body, cursor_path, click_handler = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    data = json.loads(body or "{}")
except Exception:
    data = {"events": [], "count": 0, "cursor": 0}
events = data.get("events") or []
if not events:
    sys.exit(0)

use_notifier = subprocess.run(
    ["which", "terminal-notifier"], capture_output=True).returncode == 0

for e in events:
    etype = e.get("type")
    mid = e.get("message_id", "")
    preview = (e.get("preview") or "").replace('"', "'")
    if etype == "reply":
        person = e.get("author", "")
        title = "PluribusAI"
        msg = f"{person} replied on {mid}"
        args = ["--type", "reply", "--message-id", mid, "--author", person,
                "--preview", preview]
    else:
        person = e.get("sender", "")
        title = "PluribusAI"
        msg = f"New message from {person}"
        args = ["--type", "message", "--message-id", mid, "--sender", person,
                "--preview", preview]

    if use_notifier:
        cmd = " ".join([shlex.quote("python3"), shlex.quote(click_handler)]
                       + [shlex.quote(a) for a in args])
        subprocess.run(
            ["terminal-notifier", "-title", title, "-message", msg,
             "-sound", "Glass", "-execute", cmd],
            check=False)
    else:
        subprocess.run(["osascript", "-e",
            f'display notification "{msg}" with title "{title}" sound name "Glass"'],
            check=False)

open(cursor_path, "w").write(str(data.get("cursor", 0)))
PY
  refresh_inbox
done