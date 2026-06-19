"""Schema version tracking for SQLite and Postgres stores."""

SCHEMA_VERSION = 1


def ensure_sqlite(conn):
    conn.execute("""CREATE TABLE IF NOT EXISTS schema_version (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        version INTEGER NOT NULL)""")
    row = conn.execute("SELECT version FROM schema_version WHERE id = 1").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO schema_version (id, version) VALUES (1, ?)",
            (SCHEMA_VERSION,))
        return
    current = int(row[0])
    if current > SCHEMA_VERSION:
        raise RuntimeError(
            f"database schema v{current} is newer than server (v{SCHEMA_VERSION})")
    if current < SCHEMA_VERSION:
        for v in range(current + 1, SCHEMA_VERSION + 1):
            _apply_sqlite(conn, v)
        conn.execute(
            "UPDATE schema_version SET version = ? WHERE id = 1",
            (SCHEMA_VERSION,))


def _apply_sqlite(conn, version):
    if version == 1:
        return
    raise RuntimeError(f"unknown sqlite migration {version}")


def ensure_postgres(cursor):
    cursor.execute("""CREATE TABLE IF NOT EXISTS schema_version (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        version INTEGER NOT NULL)""")
    cursor.execute("SELECT version FROM schema_version WHERE id = 1")
    row = cursor.fetchone()
    if row is None:
        cursor.execute(
            "INSERT INTO schema_version (id, version) VALUES (1, %s)",
            (SCHEMA_VERSION,))
        return
    current = int(row[0])
    if current > SCHEMA_VERSION:
        raise RuntimeError(
            f"database schema v{current} is newer than server (v{SCHEMA_VERSION})")
    if current < SCHEMA_VERSION:
        for v in range(current + 1, SCHEMA_VERSION + 1):
            _apply_postgres(cursor, v)
        cursor.execute(
            "UPDATE schema_version SET version = %s WHERE id = 1",
            (SCHEMA_VERSION,))


def _apply_postgres(cursor, version):
    if version == 1:
        return
    raise RuntimeError(f"unknown postgres migration {version}")