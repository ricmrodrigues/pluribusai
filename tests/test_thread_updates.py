#!/usr/bin/env python3
"""Thread updates: unread replies on participated threads."""

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


msg = s.send_message("ricardo", "all", "cross-model test")
mid = msg["message_id"]
time.sleep(0.01)

empty = s.get_thread_updates("ricardo")
check("sender with no replies yet has no thread updates", empty["count"] == 0)

s.read_message(mid, "ana")
time.sleep(0.01)
s.reply_message(mid, "ana", "Got it from Claude Sonnet")
time.sleep(0.01)

upd = s.get_thread_updates("ricardo")
check("original sender sees unread reply",
      upd["count"] == 1 and upd["threads"][0]["message_id"] == mid)
check("unread_replies count is 1", upd["threads"][0]["unread_replies"] == 1)
check("latest reply author is ana",
      upd["threads"][0]["latest_reply"]["author"] == "ana")

s.reply_message(mid, "ricardo", "thanks ana")
time.sleep(0.01)
s.reply_message(mid, "ana", "np")
time.sleep(0.01)

after = s.get_thread_updates("ricardo")
check("after ricardo replies, ana's newer reply is unread",
      after["count"] == 1 and after["threads"][0]["unread_replies"] == 1)

unrelated = s.send_message("ricardo", ["luciano"], "private")
time.sleep(0.01)
s.reply_message(unrelated["message_id"], "luciano", "got it")
time.sleep(0.01)
ana_upd = s.get_thread_updates("ana")
check("unrelated thread not in ana updates",
      unrelated["message_id"] not in {t["message_id"] for t in ana_upd["threads"]})

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall thread_updates checks passed")