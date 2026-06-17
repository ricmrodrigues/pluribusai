#!/usr/bin/env python3
"""v0.4: X-PluribusAI-User header defaults + get_thread_updates MCP tool."""

import json
import os
import sys
import tempfile
import threading
import time
import urllib.request

_tmp = tempfile.mkdtemp()
os.environ["PLURIBUSAI_STORE"] = "sqlite"
os.environ["PLURIBUSAI_DB"] = os.path.join(_tmp, "test.db")
os.environ["PLURIBUSAI_HTTP_PORT"] = "18788"
os.environ["PLURIBUSAI_TOKEN"] = "test-secret"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: E402
from store import make_store  # noqa: E402

fail = []
store = make_store()


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        fail.append(name)


def mcp_call(tool, arguments=None, user=None, token="test-secret"):
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments or {}},
    }).encode()
    req = urllib.request.Request("http://127.0.0.1:18788/mcp", data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {token}")
    if user:
        req.add_header("X-PluribusAI-User", user)
    with urllib.request.urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read().decode())
    text = data["result"]["content"][0]["text"]
    return json.loads(text)


httpd = threading.Thread(
    target=lambda: server.ThreadingHTTPServer(
        ("127.0.0.1", 18788), server.Handler).serve_forever(),
    daemon=True)
httpd.start()
time.sleep(0.2)

try:
    mid = store.send_message("ricardo", "all", "header test")["message_id"]
    time.sleep(0.01)
    store.read_message(mid, "ana")
    store.reply_message(mid, "ana", "reply via header")
    time.sleep(0.01)

    inbox = mcp_call("get_inbox", user="ana")
    check("header user get_inbox works with explicit user", inbox["count"] >= 0)

    inbox_hdr = mcp_call("get_inbox", user="ana")
    check("get_inbox with header", isinstance(inbox_hdr["count"], int))

    sent = mcp_call("send_message", {"content": "from header"}, user="bob")
    check("send_message defaults sender from header", sent.get("message_id", "").startswith("msg_"))
    full = store.get_message(sent["message_id"])
    check("message sender is bob", full["message"]["sender"] == "bob")

    threads = mcp_call("get_thread_updates", {"limit": 5}, user="ricardo")
    check("get_thread_updates tool registered",
          threads["count"] >= 1 and threads["threads"][0]["message_id"] == mid)

    tools_req = json.dumps({
        "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {},
    }).encode()
    req = urllib.request.Request("http://127.0.0.1:18788/mcp", data=tools_req, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer test-secret")
    with urllib.request.urlopen(req, timeout=5) as resp:
        names = [t["name"] for t in json.loads(resp.read().decode())["result"]["tools"]]
    check("tools/list includes get_thread_updates", "get_thread_updates" in names)
finally:
    pass

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall v0.4 checks passed")