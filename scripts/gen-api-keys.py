#!/usr/bin/env python3
"""Generate per-user API keys for PLURIBUSAI_API_KEYS_FILE.

Usage:
  python3 scripts/gen-api-keys.py alice bob carol > api-keys.json
"""
import json
import secrets
import sys


def main():
    users = [u.strip() for u in sys.argv[1:] if u.strip()]
    if not users:
        print("usage: gen-api-keys.py <user> [<user> ...]", file=sys.stderr)
        return 2
    keys = {u: f"pk_{secrets.token_urlsafe(24)}" for u in users}
    print(json.dumps(keys, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())