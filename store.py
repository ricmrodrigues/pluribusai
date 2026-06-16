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


def _default_db_path():
    return os.path.expanduser("~/.pluribusai/data/queue.db")


def make_store():
    backend = os.environ.get("PLURIBUSAI_STORE", "sqlite").lower()
    if backend == "postgres":
        return PostgresStore()
    db = os.environ.get("PLURIBUSAI_DB") or _default_db_path()
    return SqliteStore(db)
