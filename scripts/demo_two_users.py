#!/usr/bin/env python3
"""Simulate ricardo -> ana collaboration via MCP HTTP (no IDE required)."""
import json
import os
import sys
import urllib.request

ENDPOINT = os.environ.get("PLURIBUSAI_ENDPOINT", "http://localhost:8787/mcp")
TOKEN = os.environ.get("PLURIBUSAI_TOKEN", "test-token-local-dev")


def call(tool, arguments):
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }).encode()
    req = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {TOKEN}",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
    text = data["result"]["content"][0]["text"]
    return json.loads(text)


def main():
    print("1. ricardo broadcasts to team...")
    sent = call("send_message", {
        "sender": "ricardo",
        "audience": "all",
        "kind": "mr",
        "content": "Please review PR #42 — auth refactor ready",
        "ref": "https://github.com/ricmrodrigues/pluribusai/pull/42",
    })
    mid = sent["message_id"]
    print(f"   -> {mid}")

    print("2. ana checks inbox (peek)...")
    inbox = call("get_inbox", {"user": "ana"})
    print(f"   -> {inbox['count']} unread")
    assert mid in {m["id"] for m in inbox["messages"]}, "ana should see broadcast"

    print("3. ana replies...")
    call("reply_message", {
        "message_id": mid,
        "author": "ana",
        "content": "LGTM — one nit on token expiry",
    })

    print("4. ricardo activity feed (should see ana reply)...")
    act = call("get_activity", {"user": "ricardo", "since": 0, "limit": 10})
    assert any(e["type"] == "reply" and e["author"] == "ana" for e in act["events"])
    print(f"   -> {act['count']} event(s), reply from ana detected")

    print("5. list_teammates...")
    team = call("list_teammates", {})
    names = [t["name"] for t in team["teammates"]]
    print(f"   -> {', '.join(names)}")

    print("\nTwo-user loop OK — server is ready for real agents.")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"FAILED: {e}", file=sys.stderr)
        sys.exit(1)