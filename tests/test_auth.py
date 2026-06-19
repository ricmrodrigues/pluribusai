#!/usr/bin/env python3
"""v0.6: per-user API keys and shared token auth."""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from auth import AuthConfig, load_auth_config  # noqa: E402

fail = []


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        fail.append(name)


cfg = AuthConfig(shared_token="team-secret", user_keys={"alice": "pk_alice"})
check("shared token accepts", cfg.resolve("Bearer team-secret", "bob") == (True, "bob"))
check("alice key resolves user",
      cfg.resolve("Bearer pk_alice", None) == (True, "alice"))
check("alice key + matching header",
      cfg.resolve("Bearer pk_alice", "alice") == (True, "alice"))
check("alice key rejects wrong header",
      cfg.resolve("Bearer pk_alice", "bob") == (False, None))
check("bad token rejected", cfg.resolve("Bearer wrong", "alice") == (False, None))

off = AuthConfig()
check("auth disabled allows all", off.resolve(None, "any") == (True, "any"))

tmp = tempfile.mkdtemp()
path = os.path.join(tmp, "keys.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump({"carol": "pk_carol"}, f)
os.environ["PLURIBUSAI_API_KEYS_FILE"] = path
os.environ.pop("PLURIBUSAI_TOKEN", None)
loaded = load_auth_config()
check("load from file", loaded.user_keys.get("carol") == "pk_carol")
check("file key auth", loaded.resolve("Bearer pk_carol", None) == (True, "carol"))
os.environ.pop("PLURIBUSAI_API_KEYS_FILE", None)

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall auth checks passed")