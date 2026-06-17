#!/usr/bin/env python3
"""Activity feed: messages, replies on participated threads, since cursor."""

import os
import sys
import tempfile
import time

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


def types(events):
    return [e["type"] for e in events]


# broadcast; luciano should see message activity
b = s.send_message("ricardo", "all", "team standup notes")
bid = b["message_id"]
t0 = time.time()
time.sleep(0.01)

act = s.get_activity("luciano", since=0)
check("new broadcast is message activity for recipient",
      any(e["type"] == "message" and e["message_id"] == bid for e in act["events"]))

# ricardo (sender) should not get activity for own broadcast
act_sender = s.get_activity("ricardo", since=0)
check("sender does not get activity for own broadcast",
      bid not in {e.get("message_id") for e in act_sender["events"]})

# luciano reads; ana replies — ricardo (thread author) should see reply activity
s.read_message(bid, "luciano")
time.sleep(0.01)
since = t0
s.reply_message(bid, "ana", "sounds good")
time.sleep(0.01)

act_ric = s.get_activity("ricardo", since=since)
check("reply activity reaches original sender",
      any(e["type"] == "reply" and e["message_id"] == bid and e["author"] == "ana"
          for e in act_ric["events"]))

cursor = act_ric["cursor"]
check("cursor advances", cursor > since)
act_old = s.get_activity("ricardo", since=cursor)
check("since cursor suppresses replayed events", act_old["count"] == 0)

# unrelated thread should not notify ana
other = s.send_message("ricardo", ["luciano"], "private ping")
time.sleep(0.01)
s.reply_message(other["message_id"], "luciano", "got it")
time.sleep(0.01)
act_ana = s.get_activity("ana", since=since)
check("reply on unrelated thread not in ana activity",
      other["message_id"] not in {e.get("message_id") for e in act_ana["events"]})

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall activity checks passed")