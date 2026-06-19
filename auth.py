"""Bearer auth: shared token, per-user API keys, and optional control-plane JWT."""
import json
import os
import urllib.error
import urllib.request

try:
    import jwt as _jwt
except ImportError:
    _jwt = None


def _parse_keys_blob(raw):
    data = json.loads(raw)
    if isinstance(data, dict):
        return {str(user).strip(): str(token).strip()
                for user, token in data.items() if user and token}
    if isinstance(data, list):
        out = {}
        for item in data:
            if not isinstance(item, dict):
                continue
            user = str(item.get("user", "")).strip()
            token = str(item.get("token", "")).strip()
            if user and token:
                out[user] = token
        return out
    raise ValueError("API keys must be a JSON object or list of {user, token}")


def load_user_keys():
    """Return {username: bearer_token} from file or inline env."""
    path = os.environ.get("PLURIBUSAI_API_KEYS_FILE", "").strip()
    inline = os.environ.get("PLURIBUSAI_API_KEYS", "").strip()
    if path:
        with open(path, encoding="utf-8") as f:
            return _parse_keys_blob(f.read())
    if inline:
        return _parse_keys_blob(inline)
    return {}


def _validate_jwt(token, secret, issuer):
    if not _jwt or not secret:
        return None
    try:
        claims = _jwt.decode(
            token, secret, algorithms=["HS256"],
            issuer=issuer,
            options={"require": ["exp", "sub", "username"]})
    except Exception:
        return None
    username = (claims.get("username") or "").strip()
    return username or None


def _validate_pk_via_control_plane(token, base_url, internal_secret):
    url = base_url.rstrip("/") + "/internal/validate-key"
    payload = json.dumps({"key": token}).encode()
    req = urllib.request.Request(
        url, data=payload, method="POST",
        headers={
            "Content-Type": "application/json",
            "X-PluribusAI-Internal": internal_secret,
        })
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = json.loads(resp.read().decode())
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError):
        return None
    if not body.get("valid"):
        return None
    return (body.get("username") or "").strip() or None


class AuthConfig:
    def __init__(
        self,
        shared_token=None,
        user_keys=None,
        jwt_secret=None,
        jwt_issuer="pluribusai-control",
        control_plane_url=None,
        internal_secret=None,
    ):
        self.shared_token = (shared_token or "").strip() or None
        self.user_keys = dict(user_keys or {})
        self.token_to_user = {tok: user for user, tok in self.user_keys.items()}
        self.jwt_secret = (jwt_secret or "").strip() or None
        self.jwt_issuer = (jwt_issuer or "pluribusai-control").strip()
        self.control_plane_url = (control_plane_url or "").strip() or None
        self.internal_secret = (internal_secret or "").strip() or None

    @property
    def enabled(self):
        return bool(
            self.shared_token
            or self.token_to_user
            or self.jwt_secret
            or (self.control_plane_url and self.internal_secret))

    def resolve(self, authorization_header, header_user=None):
        """Return (ok, user) where user may be set from the matched key."""
        if not self.enabled:
            return True, (header_user or "").strip() or None

        if not authorization_header or not authorization_header.startswith("Bearer "):
            return False, None
        token = authorization_header[7:].strip()
        if not token:
            return False, None

        header_user = (header_user or "").strip() or None

        if self.shared_token and token == self.shared_token:
            return True, header_user

        key_user = self.token_to_user.get(token)
        if key_user:
            if header_user and header_user != key_user:
                return False, None
            return True, key_user

        if self.jwt_secret:
            jwt_user = _validate_jwt(token, self.jwt_secret, self.jwt_issuer)
            if jwt_user:
                if header_user and header_user != jwt_user:
                    return False, None
                return True, jwt_user

        if (token.startswith("pk_")
                and self.control_plane_url
                and self.internal_secret):
            cp_user = _validate_pk_via_control_plane(
                token, self.control_plane_url, self.internal_secret)
            if cp_user:
                if header_user and header_user != cp_user:
                    return False, None
                return True, cp_user

        return False, None


def load_auth_config():
    return AuthConfig(
        shared_token=os.environ.get("PLURIBUSAI_TOKEN"),
        user_keys=load_user_keys(),
        jwt_secret=os.environ.get("PLURIBUSAI_JWT_SECRET"),
        jwt_issuer=os.environ.get("PLURIBUSAI_JWT_ISSUER", "pluribusai-control"),
        control_plane_url=os.environ.get("PLURIBUSAI_CONTROL_PLANE_URL"),
        internal_secret=os.environ.get("PLURIBUSAI_INTERNAL_SECRET"),
    )