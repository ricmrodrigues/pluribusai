#!/usr/bin/env python3
"""v0.6: activity hub, metrics, migrations, observability."""

import json
import os
import sys
import tempfile
import threading
import time

_tmp = tempfile.mkdtemp()
os.environ["PLURIBUSAI_STORE"] = "sqlite"
os.environ["PLURIBUSAI_DB"] = os.path.join(_tmp, "v06.db")
os.environ["PLURIBUSAI_HTTP_PORT"] = "18788"
os.environ["PLURIBUSAI_TOKEN"] = "v06-secret"
os.environ["PLURIBUSAI_LOG_FORMAT"] = "json"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server  # noqa: E402
from activity_hub import ActivityHub  # noqa: E402
from migrations import SCHEMA_VERSION  # noqa: E402
from observability import Metrics  # noqa: E402
from store import make_store, set_activity_notifier  # noqa: E402

fail = []


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        fail.append(name)


hub = ActivityHub()
set_activity_notifier(hub.notify)
store = make_store()

calls = {"n": 0}

def fetch():
    calls["n"] += 1
    if calls["n"] < 2:
        return {"events": [], "count": 0, "cursor": 0}
    return {"events": [{"type": "message"}], "count": 1, "cursor": 1}

def poke():
    time.sleep(0.2)
    hub.notify()

threading.Thread(target=poke, daemon=True).start()
t0 = time.time()
result = hub.wait_for_activity(fetch, timeout=3)
check("hub wakes before timeout", result["count"] == 1 and time.time() - t0 < 2.5)

m = Metrics()
m.inc_request("GET", "/health", 200)
body = m.render_prometheus("0.6.0")
check("metrics include request counter", "pluribusai_http_requests_total" in body)
check("metrics include version info", 'version="0.6.0"' in body)

import sqlite3
conn = sqlite3.connect(os.environ["PLURIBUSAI_DB"])
row = conn.execute("SELECT version FROM schema_version WHERE id = 1").fetchone()
check("schema version recorded", row and int(row[0]) == SCHEMA_VERSION)

import urllib.request

httpd = threading.Thread(
    target=lambda: server.ThreadingHTTPServer(
        ("127.0.0.1", 18788), server.Handler).serve_forever(),
    daemon=True)
httpd.start()
time.sleep(0.2)

req = urllib.request.Request("http://127.0.0.1:18788/health")
with urllib.request.urlopen(req, timeout=3) as resp:
    health = json.loads(resp.read().decode())
check("health version 0.6", health.get("version") == "0.6.0")
check("health reports auth on", health.get("auth") == "on")

req = urllib.request.Request("http://127.0.0.1:18788/metrics")
with urllib.request.urlopen(req, timeout=3) as resp:
    metrics = resp.read().decode()
check("metrics endpoint live", "pluribusai_up 1" in metrics)

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall v0.6 checks passed")