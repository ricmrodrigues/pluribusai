#!/usr/bin/env python3
"""v0.5: toast click handler — prompt, focus.json, consume."""

import json
import os
import sys
import tempfile
import time

_tmp = tempfile.mkdtemp()
os.environ["HOME"] = _tmp
os.environ["USERPROFILE"] = _tmp

import importlib.util

_handler_path = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "install", "click-handler.py")
_spec = importlib.util.spec_from_file_location("click_handler", _handler_path)
click_handler = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(click_handler)

fail = []


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        fail.append(name)


click_handler.clear_focus()

msg_prompt = click_handler.build_prompt(
    "message", "msg_abc123", sender="ana", preview="Hello team")
check("message prompt includes id and sender",
      "msg_abc123" in msg_prompt and "ana" in msg_prompt)
check("message prompt mentions read_message",
      "read_message" in msg_prompt or "get_message" in msg_prompt)

rpl_prompt = click_handler.build_prompt(
    "reply", "msg_abc123", author="ana", preview="LGTM")
check("reply prompt includes thread id", "msg_abc123" in rpl_prompt)
check("reply prompt mentions thread updates",
      "get_thread_updates" in rpl_prompt or "get_message" in rpl_prompt)

click_handler.write_focus("message", "msg_deadbeef", sender="bob", preview="ping")
path = click_handler.focus_path()
check("focus.json written", os.path.isfile(path))
with open(path, encoding="utf-8") as f:
    data = json.load(f)
check("focus.json has prompt", "msg_deadbeef" in data.get("prompt", ""))
check("focus.json has clicked_at", data.get("clicked_at", 0) > 0)

read = click_handler.read_focus()
check("read_focus returns data", read and read["message_id"] == "msg_deadbeef")

# Stale focus ignored
data["clicked_at"] = time.time() - 7200
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
check("stale focus ignored", click_handler.read_focus() is None)

click_handler.write_focus("reply", "msg_fresh", author="ana", preview="ok")
import io
from contextlib import redirect_stdout

buf = io.StringIO()
with redirect_stdout(buf):
    rc = click_handler.consume_focus()
check("consume-focus exits 0", rc == 0)
out = buf.getvalue()
check("consume-focus prints prompt", "msg_fresh" in out)
check("consume-focus clears file", not os.path.isfile(path))

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall click_handler checks passed")