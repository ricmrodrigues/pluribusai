#!/bin/sh
# SessionStart hook — inject PluribusAI inbox summary into Claude context.
ENV="$HOME/.pluribusai/env"
[ -f "$ENV" ] || exit 0
. "$ENV"

auth=()
[ -n "$PLURIBUSAI_TOKEN" ] && auth=(-H "Authorization: Bearer $PLURIBUSAI_TOKEN")
[ -n "$PLURIBUSAI_USER" ] && auth=("${auth[@]}" -H "X-PluribusAI-User: $PLURIBUSAI_USER")

inbox_req='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_inbox","arguments":{}}}'

count=$(curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
  -H 'Content-Type: application/json' "${auth[@]}" -d "$inbox_req" 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(json.loads(d['result']['content'][0]['text'])['count'])" 2>/dev/null) || count=""

if [ -z "$count" ]; then
  echo "PluribusAI: endpoint unreachable ($PLURIBUSAI_ENDPOINT)."
  exit 0
fi

echo "PluribusAI inbox for $PLURIBUSAI_USER: $count unread message(s)."

CLICK="$HOME/.pluribusai/click-handler.py"
[ -f "$CLICK" ] && python3 "$CLICK" --consume-focus 2>/dev/null || true

act_req='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_thread_updates","arguments":{"limit":5}}}'
curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
  -H 'Content-Type: application/json' "${auth[@]}" -d "$act_req" 2>/dev/null \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
threads = json.loads(d['result']['content'][0]['text']).get('threads', [])
for t in threads[-5:]:
    lr = t.get('latest_reply', {})
    print(f\"  - [reply] {lr.get('author')} on {t.get('message_id')}: {lr.get('preview', '')}\")
" 2>/dev/null || true

echo "Use PluribusAI MCP tools (get_inbox, get_activity, read_message, reply_message) for team collaboration."