#!/usr/bin/env python3
"""HTTP surface: /health, /activity auth and long-poll return shape."""

import json
import os
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

_tmp = tempfile.mkdtemp()
os.environ["PLURIBUSAI_STORE"] = "sqlite"
os.environ["PLURIBUSAI_DB"] = os.path.join(_tmp, "test.db")
os.environ["PLURIBUSAI_HTTP_PORT"] = "18787"
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


def get(path, token=None, timeout=5):
    req = urllib.request.Request(f"http://127.0.0.1:18787{path}")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read().decode())


def post_message():
    time.sleep(0.5)
    store.send_message("alice", "all", "http activity ping")


httpd = threading.Thread(
    target=lambda: server.ThreadingHTTPServer(
        ("127.0.0.1", 18787), server.Handler).serve_forever(),
    daemon=True)
httpd.start()
time.sleep(0.2)

try:
    code, body = get("/health")
    check("health ok", code == 200 and body.get("version") == "0.4.0")

    try:
        get("/activity?user=bob&since=0&timeout=1")
        check("activity requires auth", False)
    except urllib.error.HTTPError as e:
        check("activity requires auth", e.code == 401)

    code, body = get("/activity?user=bob&since=0&timeout=1&limit=10", token="test-secret")
    check("activity returns shape", code == 200 and "events" in body and "cursor" in body)

    t = threading.Thread(target=post_message, daemon=True)
    t.start()
    code, body = get("/activity?user=bob&since=0&timeout=5&limit=10", token="test-secret",
                     timeout=8)
    check("long-poll delivers message activity",
          code == 200 and body.get("count", 0) >= 1)
finally:
    pass

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall http checks passed")