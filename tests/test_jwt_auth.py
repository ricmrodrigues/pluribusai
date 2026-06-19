#!/usr/bin/env python3
"""JWT and control-plane API key validation in auth.py."""

import json
import os
import sys
import tempfile
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    import jwt
except ImportError:
    print("SKIP: PyJWT not installed")
    sys.exit(0)

from auth import AuthConfig, load_auth_config  # noqa: E402

fail = []
SECRET = "test-jwt-secret"
ISSUER = "pluribusai-control"


def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond:
        fail.append(name)


def make_jwt(username="alice"):
    now = int(time.time())
    return jwt.encode({
        "iss": ISSUER,
        "sub": "user123",
        "username": username,
        "org_id": "org1",
        "org_slug": "alice",
        "iat": now,
        "exp": now + 3600,
        "scope": "mcp",
    }, SECRET, algorithm="HS256")


class _ValidateHandler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        if self.path != "/internal/validate-key":
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length).decode())
        key = body.get("key", "")
        if key == "pk_valid":
            payload = {"valid": True, "username": "bob"}
        else:
            payload = {"valid": False}
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


httpd = HTTPServer(("127.0.0.1", 19876), _ValidateHandler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
time.sleep(0.1)

cfg = AuthConfig(jwt_secret=SECRET, jwt_issuer=ISSUER)
token = make_jwt("alice")
check("jwt resolves user", cfg.resolve(f"Bearer {token}", None) == (True, "alice"))
check("jwt + matching header",
      cfg.resolve(f"Bearer {token}", "alice") == (True, "alice"))
check("jwt rejects wrong header",
      cfg.resolve(f"Bearer {token}", "bob") == (False, None))
check("bad jwt rejected", cfg.resolve("Bearer not-a-jwt", "alice") == (False, None))

cp_cfg = AuthConfig(
    control_plane_url="http://127.0.0.1:19876",
    internal_secret="internal",
)
check("pk via control plane",
      cp_cfg.resolve("Bearer pk_valid", None) == (True, "bob"))
check("invalid pk rejected",
      cp_cfg.resolve("Bearer pk_nope", None) == (False, None))

os.environ["PLURIBUSAI_JWT_SECRET"] = SECRET
os.environ["PLURIBUSAI_JWT_ISSUER"] = ISSUER
loaded = load_auth_config()
check("load jwt from env", loaded.jwt_secret == SECRET)
check("loaded jwt auth",
      loaded.resolve(f"Bearer {make_jwt('carol')}", None) == (True, "carol"))
os.environ.pop("PLURIBUSAI_JWT_SECRET", None)
os.environ.pop("PLURIBUSAI_JWT_ISSUER", None)

httpd.shutdown()

if fail:
    print(f"\n{len(fail)} FAILURES: {fail}")
    sys.exit(1)
print("\nall jwt auth checks passed")