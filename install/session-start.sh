#!/bin/sh
# SessionStart hook — inject PluribusAI inbox summary into Claude context.
ENV="$HOME/.pluribusai/env"
[ -f "$ENV" ] || exit 0
. "$ENV"

auth=()
[ -n "$PLURIBUSAI_TOKEN" ] && auth=(-H "Authorization: Bearer $PLURIBUSAI_TOKEN")

inbox_req="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"get_inbox\",\"arguments\":{\"user\":\"$PLURIBUSAI_USER\"}}}"

count=$(curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
  -H 'Content-Type: application/json' "${auth[@]}" -d "$inbox_req" 2>/dev/null \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(json.loads(d['result']['content'][0]['text'])['count'])" 2>/dev/null) || count=""

if [ -z "$count" ]; then
  echo "PluribusAI: endpoint unreachable ($PLURIBUSAI_ENDPOINT)."
  exit 0
fi

echo "PluribusAI inbox for $PLURIBUSAI_USER: $count unread message(s)."

if [ "$count" != "0" ]; then
  act_req="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_activity\",\"arguments\":{\"user\":\"$PLURIBUSAI_USER\",\"since\":0,\"limit\":5}}}"
  curl -s --max-time 8 -X POST "$PLURIBUSAI_ENDPOINT/mcp" \
    -H 'Content-Type: application/json' "${auth[@]}" -d "$act_req" 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
for e in json.loads(d['result']['content'][0]['text'])['events'][-5:]:
    if e['type'] == 'message':
        print(f\"  - [new] {e['sender']}: {e['preview']} ({e['message_id']})\")
    else:
        print(f\"  - [reply] {e['author']} on {e['message_id']}: {e['preview']}\")
" 2>/dev/null || true
fi

echo "Use PluribusAI MCP tools (get_inbox, get_activity, read_message, reply_message) for team collaboration."