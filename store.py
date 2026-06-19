"""
Storage backends for PluribusAI.

Messaging model: a message is sent to an audience ("all" = broadcast, or
a list of usernames = targeted) and has PER-RECIPIENT read state. The same
message is unread for one person and read for another at the same time, tracked
in a separate message_reads table. Messages persist as history; reading only
marks-read for the calling user, never deletes. Replies are append-only and
never "close" a message (no claim-once semantics).

Two interchangeable stores behind one interface:
  - SqliteStore   : zero-dep, single file, for local dev / single-replica.
  - PostgresStore : pg8000 (pure-python) + Aurora IAM auth, for the cluster.
Pick via PLURIBUSAI_STORE=sqlite|postgres.

Aurora rule: IAM auth only, token generated fresh per connection, never stored.
"""

import json
import os
import sqlite3
import time
import uuid

from migrations import ensure_postgres, ensure_sqlite

_activity_notifier = None


def set_activity_notifier(fn):
    global _activity_notifier
    _activity_notifier = fn


def _notify_activity():
    if _activity_notifier:
        try:
            _activity_notifier()
        except Exception:
            pass


def _now():
    return time.time()


def _mid():
    return "msg_" + uuid.uuid4().hex[:10]


def _pid():
    return "rpl_" + uuid.uuid4().hex[:10]


def _audience_to_str(audience):
    # "all" or list[str] -> canonical json text
    if audience in (None, "all", "ALL", "*"):
        return json.dumps("all")
    if isinstance(audience, str):
        return json.dumps([audience])
    return json.dumps(list(audience))


def _audience_from_str(s):
    try:
        return json.loads(s)
    except Exception:
        return "all"


def _addressed_to(audience_val, user):
    # is `user` a recipient of this audience?
    if audience_val == "all":
        return True
    if isinstance(audience_val, list):
        return user in audience_val
    return False


def _preview(text, n=120):
    if not text:
        return ""
    s = str(text).replace("\n", " ").strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def _activity_result(events, since, limit):
    events = sorted(events, key=lambda e: e["created_at"])[: int(limit)]
    cursor = max((e["created_at"] for e in events), default=float(since))
    return {"events": events, "count": len(events), "cursor": cursor}


def _audience_names(audience_str):
    aud = _audience_from_str(audience_str)
    return aud if isinstance(aud, list) else []


def _bump_activity(activity, name, ts):
    if not name or name == "unknown":
        return
    activity[name] = max(activity.get(name, 0), float(ts))


def _snippet(text, query, n=160):
    if not text:
        return ""
    low = str(text).lower()
    q = str(query).lower().strip()
    i = low.find(q) if q else -1
    if i < 0:
        return _preview(text, n)
    start = max(0, i - 40)
    excerpt = str(text)[start: start + n].replace("\n", " ")
    prefix = "…" if start > 0 else ""
    suffix = "…" if start + n < len(text) else ""
    return prefix + excerpt.strip() + suffix


# --------------------------------------------------------------------------- #
# SQLite
# --------------------------------------------------------------------------- #

class SqliteStore:
    def __init__(self, path):
        self.path = path
        self._init()

    def _conn(self):
        c = sqlite3.connect(self.path, timeout=10)
        c.row_factory = sqlite3.Row
        c.execute("PRAGMA journal_mode=WAL")
        return c

    def _init(self):
        with self._conn() as c:
            ensure_sqlite(c)
            c.execute("""CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY, sender TEXT NOT NULL, audience TEXT NOT NULL,
                kind TEXT NOT NULL, content TEXT, ref TEXT,
                created_at REAL NOT NULL)""")
            c.execute("""CREATE TABLE IF NOT EXISTS message_reads (
                message_id TEXT NOT NULL, user TEXT NOT NULL, read_at REAL NOT NULL,
                PRIMARY KEY (message_id, user))""")
            c.execute("""CREATE TABLE IF NOT EXISTS message_replies (
                id TEXT PRIMARY KEY, message_id TEXT NOT NULL, author TEXT NOT NULL,
                content TEXT NOT NULL, created_at REAL NOT NULL)""")

    def send_message(self, sender, audience, content, kind="text", ref=None):
        mid = _mid()
        with self._conn() as c:
            c.execute("INSERT INTO messages (id,sender,audience,kind,content,ref,"
                      "created_at) VALUES (?,?,?,?,?,?,?)",
                      (mid, sender, _audience_to_str(audience), kind, content, ref,
                       _now()))
        _notify_activity()
        return {"message_id": mid, "audience": _audience_from_str(_audience_to_str(audience))}

    def get_inbox(self, user):
        # PEEK ONLY — never marks read. Unread messages addressed to `user`,
        # excluding the user's own sends.
        with self._conn() as c:
            rows = [dict(r) for r in c.execute(
                "SELECT m.* FROM messages m WHERE m.sender != ? AND NOT EXISTS "
                "(SELECT 1 FROM message_reads r WHERE r.message_id=m.id AND r.user=?) "
                "ORDER BY m.created_at ASC", (user, user)).fetchall()]
        inbox = []
        for r in rows:
            aud = _audience_from_str(r["audience"])
            if _addressed_to(aud, user):
                r["audience"] = aud
                inbox.append(r)
        return {"messages": inbox, "count": len(inbox)}

    def read_message(self, message_id, user):
        with self._conn() as c:
            if c.execute("SELECT 1 FROM messages WHERE id=?", (message_id,)).fetchone() is None:
                raise ValueError(f"no such message: {message_id}")
            c.execute("INSERT OR IGNORE INTO message_reads (message_id,user,read_at) "
                      "VALUES (?,?,?)", (message_id, user, _now()))
        return {"message_id": message_id, "read_by": user, "status": "read"}

    def reply_message(self, message_id, author, content):
        pid = _pid()
        with self._conn() as c:
            if c.execute("SELECT 1 FROM messages WHERE id=?", (message_id,)).fetchone() is None:
                raise ValueError(f"no such message: {message_id}")
            c.execute("INSERT INTO message_replies (id,message_id,author,content,"
                      "created_at) VALUES (?,?,?,?,?)",
                      (pid, message_id, author, content, _now()))
            # a reply implies the author has seen the message
            c.execute("INSERT OR IGNORE INTO message_reads (message_id,user,read_at) "
                      "VALUES (?,?,?)", (message_id, author, _now()))
        _notify_activity()
        return {"reply_id": pid, "message_id": message_id}

    def get_message(self, message_id):
        with self._conn() as c:
            m = c.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
            if m is None:
                raise ValueError(f"no such message: {message_id}")
            m = dict(m)
            replies = [dict(r) for r in c.execute(
                "SELECT * FROM message_replies WHERE message_id=? ORDER BY created_at",
                (message_id,))]
            reads = [dict(r) for r in c.execute(
                "SELECT user,read_at FROM message_reads WHERE message_id=? "
                "ORDER BY read_at", (message_id,))]
        m["audience"] = _audience_from_str(m["audience"])
        return {"message": m, "replies": replies, "read_by": reads}

    def list_recent(self, limit=30):
        with self._conn() as c:
            rows = [dict(r) for r in c.execute(
                "SELECT * FROM messages ORDER BY created_at DESC LIMIT ?",
                (int(limit),)).fetchall()]
        for r in rows:
            r["audience"] = _audience_from_str(r["audience"])
        return {"messages": rows, "count": len(rows)}

    def _participates(self, c, user, message_id, msg_sender=None):
        if msg_sender == user:
            return True
        if c.execute("SELECT 1 FROM message_reads WHERE message_id=? AND user=?",
                      (message_id, user)).fetchone():
            return True
        if c.execute("SELECT 1 FROM message_replies WHERE message_id=? AND author=?",
                      (message_id, user)).fetchone():
            return True
        return False

    def get_activity(self, user, since=0.0, limit=50):
        since = float(since or 0)
        limit = max(1, min(int(limit or 50), 100))
        events = []
        with self._conn() as c:
            for r in c.execute(
                    "SELECT * FROM messages WHERE created_at > ? AND sender != ? "
                    "ORDER BY created_at ASC", (since, user)):
                row = dict(r)
                aud = _audience_from_str(row["audience"])
                if not _addressed_to(aud, user):
                    continue
                events.append({
                    "type": "message",
                    "id": row["id"],
                    "message_id": row["id"],
                    "sender": row["sender"],
                    "kind": row["kind"],
                    "preview": _preview(row["content"]),
                    "created_at": row["created_at"],
                })
            for r in c.execute(
                    "SELECT r.*, m.sender AS msg_sender FROM message_replies r "
                    "JOIN messages m ON m.id = r.message_id "
                    "WHERE r.created_at > ? AND r.author != ? "
                    "ORDER BY r.created_at ASC", (since, user)):
                row = dict(r)
                if not self._participates(c, user, row["message_id"], row["msg_sender"]):
                    continue
                events.append({
                    "type": "reply",
                    "id": row["id"],
                    "message_id": row["message_id"],
                    "reply_id": row["id"],
                    "author": row["author"],
                    "preview": _preview(row["content"]),
                    "created_at": row["created_at"],
                })
        return _activity_result(events, since, limit)

    def _last_touch(self, c, user, message_id, msg_sender, msg_created_at):
        touch = 0.0
        if msg_sender == user:
            touch = max(touch, float(msg_created_at))
        row = c.execute(
            "SELECT read_at FROM message_reads WHERE message_id=? AND user=?",
            (message_id, user)).fetchone()
        if row:
            touch = max(touch, float(row["read_at"]))
        for r in c.execute(
                "SELECT created_at FROM message_replies WHERE message_id=? AND author=?",
                (message_id, user)):
            touch = max(touch, float(r["created_at"]))
        return touch

    def get_thread_updates(self, user, limit=30):
        limit = max(1, min(int(limit or 30), 100))
        updates = []
        with self._conn() as c:
            for m in c.execute("SELECT * FROM messages").fetchall():
                m = dict(m)
                mid = m["id"]
                if m["sender"] != user and not self._participates(
                        c, user, mid, m["sender"]):
                    continue
                last_touch = self._last_touch(
                    c, user, mid, m["sender"], m["created_at"])
                row = c.execute(
                    "SELECT * FROM message_replies WHERE message_id=? AND author!=? "
                    "ORDER BY created_at DESC LIMIT 1", (mid, user)).fetchone()
                if not row:
                    continue
                row = dict(row)
                if float(row["created_at"]) <= last_touch:
                    continue
                unread = c.execute(
                    "SELECT COUNT(*) FROM message_replies "
                    "WHERE message_id=? AND author!=? AND created_at>?",
                    (mid, user, last_touch)).fetchone()[0]
                updates.append({
                    "message_id": mid,
                    "sender": m["sender"],
                    "kind": m["kind"],
                    "unread_replies": unread,
                    "latest_reply": {
                        "reply_id": row["id"],
                        "author": row["author"],
                        "preview": _preview(row["content"]),
                        "created_at": row["created_at"],
                    },
                })
        updates.sort(key=lambda u: u["latest_reply"]["created_at"], reverse=True)
        updates = updates[:limit]
        return {"threads": updates, "count": len(updates)}

    def list_teammates(self):
        activity = {}
        with self._conn() as c:
            for r in c.execute("SELECT sender, audience, created_at FROM messages"):
                row = dict(r)
                _bump_activity(activity, row["sender"], row["created_at"])
                for name in _audience_names(row["audience"]):
                    _bump_activity(activity, name, row["created_at"])
            for r in c.execute('SELECT "user", read_at FROM message_reads'):
                row = dict(r)
                _bump_activity(activity, row["user"], row["read_at"])
            for r in c.execute("SELECT author, created_at FROM message_replies"):
                row = dict(r)
                _bump_activity(activity, row["author"], row["created_at"])
        teammates = [
            {"name": name, "last_active": ts}
            for name, ts in sorted(activity.items(), key=lambda x: x[0])
        ]
        return {"teammates": teammates, "count": len(teammates)}

    def search_messages(self, query, limit=30, sender=None, kind=None):
        q = str(query or "").strip()
        if not q:
            raise ValueError("'query' is required")
        limit = max(1, min(int(limit or 30), 100))
        pattern = f"%{q.lower()}%"
        hits = []
        with self._conn() as c:
            msg_sql = (
                "SELECT * FROM messages WHERE ("
                "LOWER(COALESCE(content,'')) LIKE ? OR "
                "LOWER(COALESCE(ref,'')) LIKE ? OR LOWER(id) LIKE ?"
            )
            msg_params = [pattern, pattern, pattern]
            if sender:
                msg_sql += " AND LOWER(sender) = ?"
                msg_params.append(sender.lower())
            if kind:
                msg_sql += " AND kind = ?"
                msg_params.append(kind)
            msg_sql += ") ORDER BY created_at DESC"
            for row in c.execute(msg_sql, msg_params):
                row = dict(row)
                text = row.get("content") or row.get("ref") or ""
                hits.append({
                    "type": "message",
                    "message_id": row["id"],
                    "sender": row["sender"],
                    "kind": row["kind"],
                    "snippet": _snippet(text, q),
                    "created_at": row["created_at"],
                })
            rpl_sql = (
                "SELECT r.*, m.kind AS msg_kind FROM message_replies r "
                "JOIN messages m ON m.id = r.message_id WHERE "
                "LOWER(r.content) LIKE ? OR LOWER(r.id) LIKE ?"
            )
            rpl_params = [pattern, pattern]
            if sender:
                rpl_sql += " AND LOWER(r.author) = ?"
                rpl_params.append(sender.lower())
            if kind:
                rpl_sql += " AND m.kind = ?"
                rpl_params.append(kind)
            rpl_sql += " ORDER BY r.created_at DESC"
            for row in c.execute(rpl_sql, rpl_params):
                row = dict(row)
                hits.append({
                    "type": "reply",
                    "message_id": row["message_id"],
                    "reply_id": row["id"],
                    "author": row["author"],
                    "kind": row.get("msg_kind"),
                    "snippet": _snippet(row["content"], q),
                    "created_at": row["created_at"],
                })
        hits.sort(key=lambda h: h["created_at"], reverse=True)
        hits = hits[:limit]
        return {"hits": hits, "count": len(hits), "query": q}


# --------------------------------------------------------------------------- #
# Postgres (pg8000 + Aurora IAM auth)
# --------------------------------------------------------------------------- #

class PostgresStore:
    def __init__(self):
        import pg8000.dbapi  # noqa: F401
        self.host = os.environ["PGHOST"]
        self.port = int(os.environ.get("PGPORT", "5432"))
        self.dbname = os.environ.get("PGDATABASE", "pluribusai")
        self.user = os.environ.get("PGUSER", "pluribusai")
        self.region = os.environ.get("AWS_REGION", "eu-central-1")
        self._init()

    def _connect(self):
        import pg8000.dbapi
        pw = os.environ.get("PGPASSWORD")
        if pw:
            return pg8000.dbapi.connect(
                user=self.user, host=self.host, port=self.port,
                database=self.dbname, password=pw)
        import boto3
        import ssl
        token = boto3.client("rds", region_name=self.region).generate_db_auth_token(
            DBHostname=self.host, Port=self.port, DBUsername=self.user,
            Region=self.region)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return pg8000.dbapi.connect(
            user=self.user, host=self.host, port=self.port, database=self.dbname,
            password=token, ssl_context=ctx)

    def _init(self):
        c = self._connect()
        try:
            cur = c.cursor()
            ensure_postgres(cur)
            cur.execute("""CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY, sender TEXT NOT NULL, audience TEXT NOT NULL,
                kind TEXT NOT NULL, content TEXT, ref TEXT,
                created_at DOUBLE PRECISION NOT NULL)""")
            cur.execute("""CREATE TABLE IF NOT EXISTS message_reads (
                message_id TEXT NOT NULL, "user" TEXT NOT NULL,
                read_at DOUBLE PRECISION NOT NULL,
                PRIMARY KEY (message_id, "user"))""")
            cur.execute("""CREATE TABLE IF NOT EXISTS message_replies (
                id TEXT PRIMARY KEY, message_id TEXT NOT NULL, author TEXT NOT NULL,
                content TEXT NOT NULL, created_at DOUBLE PRECISION NOT NULL)""")
            c.commit()
        finally:
            c.close()

    @staticmethod
    def _dicts(cur):
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]

    def send_message(self, sender, audience, content, kind="text", ref=None):
        mid = _mid()
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute("INSERT INTO messages (id,sender,audience,kind,content,ref,"
                        "created_at) VALUES (%s,%s,%s,%s,%s,%s,%s)",
                        (mid, sender, _audience_to_str(audience), kind, content, ref,
                         _now()))
            c.commit()
        finally:
            c.close()
        _notify_activity()
        return {"message_id": mid, "audience": _audience_from_str(_audience_to_str(audience))}

    def get_inbox(self, user):
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute(
                'SELECT m.* FROM messages m WHERE m.sender != %s AND NOT EXISTS '
                '(SELECT 1 FROM message_reads r WHERE r.message_id=m.id AND r."user"=%s) '
                'ORDER BY m.created_at ASC', (user, user))
            rows = self._dicts(cur)
        finally:
            c.close()
        inbox = []
        for r in rows:
            aud = _audience_from_str(r["audience"])
            if _addressed_to(aud, user):
                r["audience"] = aud
                inbox.append(r)
        return {"messages": inbox, "count": len(inbox)}

    def read_message(self, message_id, user):
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute("SELECT 1 FROM messages WHERE id=%s", (message_id,))
            if not cur.fetchall():
                raise ValueError(f"no such message: {message_id}")
            cur.execute('INSERT INTO message_reads (message_id,"user",read_at) '
                        'VALUES (%s,%s,%s) ON CONFLICT DO NOTHING',
                        (message_id, user, _now()))
            c.commit()
        finally:
            c.close()
        return {"message_id": message_id, "read_by": user, "status": "read"}

    def reply_message(self, message_id, author, content):
        pid = _pid()
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute("SELECT 1 FROM messages WHERE id=%s", (message_id,))
            if not cur.fetchall():
                raise ValueError(f"no such message: {message_id}")
            cur.execute("INSERT INTO message_replies (id,message_id,author,content,"
                        "created_at) VALUES (%s,%s,%s,%s,%s)",
                        (pid, message_id, author, content, _now()))
            cur.execute('INSERT INTO message_reads (message_id,"user",read_at) '
                        'VALUES (%s,%s,%s) ON CONFLICT DO NOTHING',
                        (message_id, author, _now()))
            c.commit()
        finally:
            c.close()
        _notify_activity()
        return {"reply_id": pid, "message_id": message_id}

    def get_message(self, message_id):
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute("SELECT * FROM messages WHERE id=%s", (message_id,))
            m = self._dicts(cur)
            if not m:
                raise ValueError(f"no such message: {message_id}")
            m = m[0]
            cur.execute("SELECT * FROM message_replies WHERE message_id=%s "
                        "ORDER BY created_at", (message_id,))
            replies = self._dicts(cur)
            cur.execute('SELECT "user",read_at FROM message_reads WHERE message_id=%s '
                        "ORDER BY read_at", (message_id,))
            reads = self._dicts(cur)
        finally:
            c.close()
        m["audience"] = _audience_from_str(m["audience"])
        return {"message": m, "replies": replies, "read_by": reads}

    def list_recent(self, limit=30):
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute("SELECT * FROM messages ORDER BY created_at DESC LIMIT %s",
                        (int(limit),))
            rows = self._dicts(cur)
        finally:
            c.close()
        for r in rows:
            r["audience"] = _audience_from_str(r["audience"])
        return {"messages": rows, "count": len(rows)}

    def _participates(self, cur, user, message_id, msg_sender=None):
        if msg_sender == user:
            return True
        cur.execute('SELECT 1 FROM message_reads WHERE message_id=%s AND "user"=%s',
                    (message_id, user))
        if cur.fetchall():
            return True
        cur.execute("SELECT 1 FROM message_replies WHERE message_id=%s AND author=%s",
                    (message_id, user))
        return bool(cur.fetchall())

    def get_activity(self, user, since=0.0, limit=50):
        since = float(since or 0)
        limit = max(1, min(int(limit or 50), 100))
        events = []
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute(
                "SELECT * FROM messages WHERE created_at > %s AND sender != %s "
                "ORDER BY created_at ASC", (since, user))
            for row in self._dicts(cur):
                aud = _audience_from_str(row["audience"])
                if not _addressed_to(aud, user):
                    continue
                events.append({
                    "type": "message",
                    "id": row["id"],
                    "message_id": row["id"],
                    "sender": row["sender"],
                    "kind": row["kind"],
                    "preview": _preview(row["content"]),
                    "created_at": row["created_at"],
                })
            cur.execute(
                "SELECT r.*, m.sender AS msg_sender FROM message_replies r "
                "JOIN messages m ON m.id = r.message_id "
                "WHERE r.created_at > %s AND r.author != %s "
                "ORDER BY r.created_at ASC", (since, user))
            for row in self._dicts(cur):
                if not self._participates(cur, user, row["message_id"], row["msg_sender"]):
                    continue
                events.append({
                    "type": "reply",
                    "id": row["id"],
                    "message_id": row["message_id"],
                    "reply_id": row["id"],
                    "author": row["author"],
                    "preview": _preview(row["content"]),
                    "created_at": row["created_at"],
                })
        finally:
            c.close()
        return _activity_result(events, since, limit)

    def _last_touch(self, cur, user, message_id, msg_sender, msg_created_at):
        touch = 0.0
        if msg_sender == user:
            touch = max(touch, float(msg_created_at))
        cur.execute(
            'SELECT read_at FROM message_reads WHERE message_id=%s AND "user"=%s',
            (message_id, user))
        rows = cur.fetchall()
        if rows:
            touch = max(touch, float(rows[0][0]))
        cur.execute(
            "SELECT created_at FROM message_replies WHERE message_id=%s AND author=%s",
            (message_id, user))
        for row in cur.fetchall():
            touch = max(touch, float(row[0]))
        return touch

    def get_thread_updates(self, user, limit=30):
        limit = max(1, min(int(limit or 30), 100))
        updates = []
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute("SELECT * FROM messages")
            for m in self._dicts(cur):
                mid = m["id"]
                if m["sender"] != user and not self._participates(
                        cur, user, mid, m["sender"]):
                    continue
                last_touch = self._last_touch(
                    cur, user, mid, m["sender"], m["created_at"])
                cur.execute(
                    "SELECT * FROM message_replies WHERE message_id=%s AND author!=%s "
                    "ORDER BY created_at DESC LIMIT 1", (mid, user))
                latest = self._dicts(cur)
                if not latest:
                    continue
                row = latest[0]
                if float(row["created_at"]) <= last_touch:
                    continue
                cur.execute(
                    "SELECT COUNT(*) FROM message_replies "
                    "WHERE message_id=%s AND author!=%s AND created_at>%s",
                    (mid, user, last_touch))
                unread = int(cur.fetchone()[0])
                updates.append({
                    "message_id": mid,
                    "sender": m["sender"],
                    "kind": m["kind"],
                    "unread_replies": unread,
                    "latest_reply": {
                        "reply_id": row["id"],
                        "author": row["author"],
                        "preview": _preview(row["content"]),
                        "created_at": row["created_at"],
                    },
                })
        finally:
            c.close()
        updates.sort(key=lambda u: u["latest_reply"]["created_at"], reverse=True)
        updates = updates[:limit]
        return {"threads": updates, "count": len(updates)}

    def list_teammates(self):
        activity = {}
        c = self._connect()
        try:
            cur = c.cursor()
            cur.execute("SELECT sender, audience, created_at FROM messages")
            for row in self._dicts(cur):
                _bump_activity(activity, row["sender"], row["created_at"])
                for name in _audience_names(row["audience"]):
                    _bump_activity(activity, name, row["created_at"])
            cur.execute('SELECT "user", read_at FROM message_reads')
            for row in self._dicts(cur):
                _bump_activity(activity, row["user"], row["read_at"])
            cur.execute("SELECT author, created_at FROM message_replies")
            for row in self._dicts(cur):
                _bump_activity(activity, row["author"], row["created_at"])
        finally:
            c.close()
        teammates = [
            {"name": name, "last_active": ts}
            for name, ts in sorted(activity.items(), key=lambda x: x[0])
        ]
        return {"teammates": teammates, "count": len(teammates)}

    def search_messages(self, query, limit=30, sender=None, kind=None):
        q = str(query or "").strip()
        if not q:
            raise ValueError("'query' is required")
        limit = max(1, min(int(limit or 30), 100))
        pattern = f"%{q.lower()}%"
        hits = []
        c = self._connect()
        try:
            cur = c.cursor()
            msg_sql = (
                "SELECT * FROM messages WHERE ("
                "LOWER(COALESCE(content,'')) LIKE %s OR "
                "LOWER(COALESCE(ref,'')) LIKE %s OR LOWER(id) LIKE %s"
            )
            msg_params = [pattern, pattern, pattern]
            if sender:
                msg_sql += " AND LOWER(sender) = %s"
                msg_params.append(sender.lower())
            if kind:
                msg_sql += " AND kind = %s"
                msg_params.append(kind)
            msg_sql += ") ORDER BY created_at DESC"
            cur.execute(msg_sql, msg_params)
            for row in self._dicts(cur):
                text = row.get("content") or row.get("ref") or ""
                hits.append({
                    "type": "message",
                    "message_id": row["id"],
                    "sender": row["sender"],
                    "kind": row["kind"],
                    "snippet": _snippet(text, q),
                    "created_at": row["created_at"],
                })
            rpl_sql = (
                "SELECT r.*, m.kind AS msg_kind FROM message_replies r "
                "JOIN messages m ON m.id = r.message_id WHERE "
                "LOWER(r.content) LIKE %s OR LOWER(r.id) LIKE %s"
            )
            rpl_params = [pattern, pattern]
            if sender:
                rpl_sql += " AND LOWER(r.author) = %s"
                rpl_params.append(sender.lower())
            if kind:
                rpl_sql += " AND m.kind = %s"
                rpl_params.append(kind)
            rpl_sql += " ORDER BY r.created_at DESC"
            cur.execute(rpl_sql, rpl_params)
            for row in self._dicts(cur):
                hits.append({
                    "type": "reply",
                    "message_id": row["message_id"],
                    "reply_id": row["id"],
                    "author": row["author"],
                    "kind": row.get("msg_kind"),
                    "snippet": _snippet(row["content"], q),
                    "created_at": row["created_at"],
                })
        finally:
            c.close()
        hits.sort(key=lambda h: h["created_at"], reverse=True)
        hits = hits[:limit]
        return {"hits": hits, "count": len(hits), "query": q}


def _default_db_path():
    return os.path.expanduser("~/.pluribusai/data/queue.db")


def make_store():
    backend = os.environ.get("PLURIBUSAI_STORE", "sqlite").lower()
    if backend == "postgres":
        return PostgresStore()
    db = os.environ.get("PLURIBUSAI_DB") or _default_db_path()
    return SqliteStore(db)
