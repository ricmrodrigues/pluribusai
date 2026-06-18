#!/usr/bin/env python3
"""
PluribusAI: a near-dependency-free MCP server — shared inbox for AI agent teams.

Transport: MCP streamable HTTP (JSON-RPC 2.0 over HTTP POST at /mcp).
Storage:   pluggable (SQLite local / Postgres) via store.py.
Auth:      optional bearer token via PLURIBUSAI_TOKEN.

Local dev is pure stdlib (SQLite). Postgres mode needs pg8000 (+ boto3 for IAM).
"""

import contextvars
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from store import make_store

VERSION = "0.5.0"

CURRENT_USER = contextvars.ContextVar("pluribusai_user", default=None)

TOKEN = os.environ.get("PLURIBUSAI_TOKEN")
PORT = int(os.environ.get("PLURIBUSAI_HTTP_PORT", "8787"))
PROTOCOL_VERSION = "2025-06-18"

STORE = make_store()


# --------------------------------------------------------------------------- #
# Tool implementations
# --------------------------------------------------------------------------- #

def _user(a, field="user"):
    u = a.get(field) or CURRENT_USER.get()
    if not u:
        raise ValueError(
            f"'{field}' is required (or set X-PluribusAI-User header)")
    return u


def _identity(a, field):
    return a.get(field) or CURRENT_USER.get() or "unknown"


def t_send_message(a):
    if not a.get("content") and not a.get("ref"):
        raise ValueError("provide 'content' (and/or 'ref')")
    return STORE.send_message(
        sender=_identity(a, "sender"),
        audience=a.get("audience", "all"),
        content=a.get("content"),
        kind=a.get("kind", "text"),
        ref=a.get("ref"))


def t_get_inbox(a):
    return STORE.get_inbox(_user(a))


def t_read_message(a):
    return STORE.read_message(a["message_id"], _user(a))


def t_reply_message(a):
    return STORE.reply_message(a["message_id"], _identity(a, "author"),
                               a["content"])


def t_get_message(a):
    return STORE.get_message(a["message_id"])


def t_list_recent(a):
    return STORE.list_recent(limit=a.get("limit", 30))


def t_get_activity(a):
    return STORE.get_activity(
        _user(a), since=a.get("since", 0), limit=a.get("limit", 50))


def t_get_thread_updates(a):
    return STORE.get_thread_updates(_user(a), limit=a.get("limit", 30))


def t_list_teammates(a):
    return STORE.list_teammates()


def t_search_messages(a):
    if not a.get("query"):
        raise ValueError("'query' is required")
    return STORE.search_messages(
        a["query"],
        limit=a.get("limit", 30),
        sender=a.get("sender"),
        kind=a.get("kind"),
    )


TOOLS = {
    "send_message": {
        "fn": t_send_message,
        "description": "Send a message to the team. Set 'audience' to \"all\" to "
                       "broadcast, or a list of usernames (e.g. [\"alice\"]) to "
                       "target specific people. Share artifacts (MR, idea, code, doc) "
                       "for review. Per-recipient read state: a broadcast clears from "
                       "each person's counter only when THEY read it.",
        "schema": {
            "type": "object",
            "properties": {
                "sender": {
                    "type": "string",
                    "description": "Your username (defaults to X-PluribusAI-User).",
                },
                "audience": {
                    "description": "\"all\" for a broadcast, or a JSON array of "
                                   "usernames to target.",
                    "oneOf": [{"type": "string"},
                              {"type": "array", "items": {"type": "string"}}],
                },
                "kind": {"type": "string",
                         "enum": ["text", "mr", "idea", "design", "snippet", "doc"]},
                "content": {"type": "string", "description": "Message / artifact text."},
                "ref": {"type": "string", "description": "Optional URL (MR, page)."},
            },
            "required": ["content"],
        },
    },
    "get_inbox": {
        "fn": t_get_inbox,
        "description": "PEEK at your unread messages (addressed to you or broadcast, "
                       "excluding your own). Does NOT mark anything read — safe for "
                       "pollers to call repeatedly. User defaults to X-PluribusAI-User.",
        "schema": {
            "type": "object",
            "properties": {
                "user": {
                    "type": "string",
                    "description": "Defaults to X-PluribusAI-User header.",
                },
            },
        },
    },
    "read_message": {
        "fn": t_read_message,
        "description": "Mark a message read FOR YOU ONLY. Clears from your counter "
                       "but stays unread for everyone else who hasn't read it.",
        "schema": {
            "type": "object",
            "properties": {
                "message_id": {"type": "string"},
                "user": {
                    "type": "string",
                    "description": "Defaults to X-PluribusAI-User header.",
                },
            },
            "required": ["message_id"],
        },
    },
    "reply_message": {
        "fn": t_reply_message,
        "description": "Reply to a message (append-only). Replying also marks the "
                       "message read for you.",
        "schema": {
            "type": "object",
            "properties": {
                "message_id": {"type": "string"},
                "author": {
                    "type": "string",
                    "description": "Defaults to X-PluribusAI-User header.",
                },
                "content": {"type": "string"},
            },
            "required": ["message_id", "content"],
        },
    },
    "get_message": {
        "fn": t_get_message,
        "description": "Get a message with all its replies and who has read it.",
        "schema": {
            "type": "object",
            "properties": {"message_id": {"type": "string"}},
            "required": ["message_id"],
        },
    },
    "list_recent": {
        "fn": t_list_recent,
        "description": "List recent messages (history), newest first, regardless of "
                       "read state or audience.",
        "schema": {
            "type": "object",
            "properties": {"limit": {"type": "integer"}},
        },
    },
    "get_activity": {
        "fn": t_get_activity,
        "description": "Activity feed for a user since a timestamp: new messages "
                       "addressed to them and replies on threads they participate in "
                       "(sender, reader, or prior replier). Use 'cursor' from the "
                       "response as the next 'since' value.",
        "schema": {
            "type": "object",
            "properties": {
                "user": {
                    "type": "string",
                    "description": "Defaults to X-PluribusAI-User header.",
                },
                "since": {
                    "type": "number",
                    "description": "Unix timestamp; return events after this time.",
                },
                "limit": {"type": "integer"},
            },
        },
    },
    "get_thread_updates": {
        "fn": t_get_thread_updates,
        "description": "Threads you participate in with unread replies since your last "
                       "read or reply. Better than get_activity for session-start summaries "
                       "(no duplicate username in every line).",
        "schema": {
            "type": "object",
            "properties": {
                "user": {
                    "type": "string",
                    "description": "Defaults to X-PluribusAI-User header.",
                },
                "limit": {"type": "integer"},
            },
        },
    },
    "list_teammates": {
        "fn": t_list_teammates,
        "description": "List usernames seen in the team inbox (senders, recipients, "
                       "readers, repliers) with last activity timestamp.",
        "schema": {"type": "object", "properties": {}},
    },
    "search_messages": {
        "fn": t_search_messages,
        "description": "Search message bodies, refs, IDs, and reply text. Returns "
                       "matching snippets newest first.",
        "schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Text to search for."},
                "limit": {"type": "integer"},
                "sender": {
                    "type": "string",
                    "description": "Optional filter: message sender or reply author.",
                },
                "kind": {
                    "type": "string",
                    "enum": ["text", "mr", "idea", "design", "snippet", "doc"],
                    "description": "Optional filter by message kind.",
                },
            },
            "required": ["query"],
        },
    },
}


def _parse_activity_query(path):
    qs = parse_qs(urlparse(path).query)
    user = (qs.get("user") or [None])[0]
    try:
        since = float((qs.get("since") or ["0"])[0])
    except (TypeError, ValueError):
        since = 0.0
    try:
        timeout = int((qs.get("timeout") or ["30"])[0])
    except (TypeError, ValueError):
        timeout = 30
    try:
        limit = int((qs.get("limit") or ["50"])[0])
    except (TypeError, ValueError):
        limit = 50
    return user, since, max(1, min(timeout, 60)), max(1, min(limit, 100))


def _wait_activity(user, since, timeout, limit):
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = STORE.get_activity(user, since=since, limit=limit)
        if result["count"] > 0:
            return result
        time.sleep(1)
    return STORE.get_activity(user, since=since, limit=limit)


def handle_rpc(msg):
    method = msg.get("method")
    mid = msg.get("id")

    if method == "initialize":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "pluribusai", "version": VERSION},
        }}

    if method == "notifications/initialized":
        return None

    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "tools": [
                {"name": n, "description": t["description"], "inputSchema": t["schema"]}
                for n, t in TOOLS.items()
            ]
        }}

    if method == "tools/call":
        params = msg.get("params", {})
        name = params.get("name")
        args = params.get("arguments", {})
        tool = TOOLS.get(name)
        if tool is None:
            return {"jsonrpc": "2.0", "id": mid,
                    "error": {"code": -32601, "message": f"unknown tool: {name}"}}
        try:
            result = tool["fn"](args)
            return {"jsonrpc": "2.0", "id": mid, "result": {
                "content": [{"type": "text", "text": json.dumps(result, indent=2)}]
            }}
        except Exception as e:
            return {"jsonrpc": "2.0", "id": mid, "result": {
                "content": [{"type": "text", "text": f"ERROR: {e}"}],
                "isError": True,
            }}

    return {"jsonrpc": "2.0", "id": mid,
            "error": {"code": -32601, "message": f"unknown method: {method}"}}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _apply_user_header(self):
        u = self.headers.get("X-PluribusAI-User")
        if u and u.strip():
            CURRENT_USER.set(u.strip())

    def _auth_ok(self):
        if not TOKEN:
            return True
        return self.headers.get("Authorization") == f"Bearer {TOKEN}"

    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._apply_user_header()
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self._send(200, {"status": "ok", "version": VERSION})
            return
        if path == "/activity":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            user, since, timeout, limit = _parse_activity_query(self.path)
            if not user:
                user = CURRENT_USER.get()
            if not user:
                self._send(400, {"error": "query param 'user' or X-PluribusAI-User required"})
                return
            self._send(200, _wait_activity(user, since, timeout, limit))
            return
        self._send(404, {"error": "not found"})

    def do_POST(self):
        self._apply_user_header()
        if self.path.rstrip("/") != "/mcp":
            self._send(404, {"error": "not found"})
            return
        if not self._auth_ok():
            self._send(401, {"error": "unauthorized"})
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            msg = json.loads(self.rfile.read(length) or "{}")
        except json.JSONDecodeError:
            self._send(400, {"jsonrpc": "2.0", "id": None,
                             "error": {"code": -32700, "message": "parse error"}})
            return
        resp = handle_rpc(msg)
        if resp is None:
            self.send_response(202)
            self.end_headers()
            return
        self._send(200, resp)


if __name__ == "__main__":
    backend = os.environ.get("PLURIBUSAI_STORE", "sqlite")
    print(f"pluribusai v{VERSION} on :{PORT}  store={backend}  "
          f"auth={'on' if TOKEN else 'OFF'}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()