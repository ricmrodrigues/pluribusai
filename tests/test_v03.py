#!/usr/bin/env python3
"""v0.3: list_teammates and search_messages."""

import os
import sys
import tempfile

_tmp = tempfile.mkdtemp()
os.environ["PLURIBUSAI_STORE"] = "sqlite"
os.environ["PLURIBUSAI_DB"] = os.path.join(_tmp, "test.db")

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from store import make_store  # noqa: E402

s = make_store()
fail = []


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        fail.append(name)


s.send_message("ricardo", "all", "please review MR-42 auth refactor")
s.send_message("ricardo", ["luciano"], "private ping for luciano")
standup = s.send_message("luciano", "all", "standup notes")
s.reply_message(standup["message_id"], "ana", "I'll take the auth task")

team = s.list_teammates()
names = {t["name"] for t in team["teammates"]}
check("list_teammates includes senders", {"ricardo", "luciano", "ana"} <= names)
check("list_teammates includes targeted recipient", "luciano" in names)
check("list_teammates has last_active", all(t["last_active"] > 0 for t in team["teammates"]))

hits = s.search_messages("auth refactor")
check("search finds message body",
      any(h["type"] == "message" and "auth" in h["snippet"].lower() for h in hits["hits"]))

hits_kind = s.search_messages("standup", kind="text")
check("search kind filter",
      all(h.get("kind") in (None, "text") for h in hits_kind["hits"]))

hits_sender = s.search_messages("task", sender="ana")
check("search sender filter limits to ana reply",
      hits_sender["count"] >= 1 and all(
          h.get("author") == "ana" or h.get("sender") == "ana" for h in hits_sender["hits"]))

try:
    s.search_messages("   ")
    check("search requires query", False)
except ValueError:
    check("search requires query", True)

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall v0.3 checks passed")