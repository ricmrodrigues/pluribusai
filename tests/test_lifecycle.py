#!/usr/bin/env python3
"""
Messaging-model test: per-recipient read state, targeting, replies, history.
Pure stdlib, runs against SQLite. Exits non-zero on failure.
"""

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


def inbox_ids(user):
    return {m["id"] for m in s.get_inbox(user)["messages"]}


# --- broadcast from ricardo ---
b = s.send_message("ricardo", "all", "hello everyone")
bid = b["message_id"]
check("broadcast created", bid.startswith("msg_") and b["audience"] == "all")

# --- it shows for luciano and ana, NOT for ricardo (own message) ---
check("broadcast in luciano inbox", bid in inbox_ids("luciano"))
check("broadcast in ana inbox", bid in inbox_ids("ana"))
check("sender does not see own broadcast", bid not in inbox_ids("ricardo"))

# --- THE KEY PROPERTY: luciano reads it -> clears for luciano, stays for ana ---
s.read_message(bid, "luciano")
check("read clears for the reader only", bid not in inbox_ids("luciano"))
check("broadcast still unread for everyone else", bid in inbox_ids("ana"))

# --- targeting: message only to luciano ---
t = s.send_message("ricardo", ["luciano"], "psst, just you")
tid = t["message_id"]
check("targeted msg reaches the target", tid in inbox_ids("luciano"))
check("targeted msg NOT in non-target inbox", tid not in inbox_ids("ana"))

# --- reply is append-only and implies read for the replier ---
s.reply_message(bid, "ana", "hi back!")
check("reply marks read for replier", bid not in inbox_ids("ana"))
got = s.get_message(bid)
check("reply stored", len(got["replies"]) == 1 and got["replies"][0]["author"] == "ana")
check("read_by tracks both readers",
      {r["user"] for r in got["read_by"]} == {"luciano", "ana"})

# --- get_inbox is PEEK ONLY: calling it must not mark read ---
before = inbox_ids("ana")          # ana still has the targeted? no—ana not targeted
_ = s.get_inbox("luciano")
_ = s.get_inbox("luciano")
check("peek does not mark read (targeted still unread for luciano)",
      tid in inbox_ids("luciano"))

# --- history: list_recent shows everything regardless of read state ---
recent = s.list_recent()
ids = {m["id"] for m in recent["messages"]}
check("history keeps all messages", bid in ids and tid in ids)

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall messaging checks passed")
