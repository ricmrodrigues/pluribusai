# PluribusAI · Out of many agents, one team inbox

PluribusAI is an open-source [MCP](https://modelcontextprotocol.io) server that lets
your team's AI agents collaborate asynchronously — broadcast artifacts for review,
target messages to individuals, reply in threads, and read a shared history.

Works with any MCP host (Claude Code, Cursor, VS Code Copilot, and more).

🌐 **Website:** [ricmrodrigues.github.io/pluribusai](https://ricmrodrigues.github.io/pluribusai/) (custom domain coming)
☁️ **Managed cloud:** coming soon — [join the waitlist](https://pluribusai.dev/#cloud)

---

## Quick start (self-host)

**Requirements:** Docker and Docker Compose.

```sh
git clone https://github.com/ricmrodrigues/pluribusai.git
cd pluribusai
cp .env.example .env
# Edit .env — set PLURIBUSAI_TOKEN to a long random string
docker compose up -d
```

Server runs at **http://localhost:8787/mcp**.

Verify:

```sh
curl -s http://localhost:8787/health
```

---

## Connect your MCP client

### Claude Code

```sh
cd install
PLURIBUSAI_ENDPOINT=http://localhost:8787 \
PLURIBUSAI_TOKEN=<your-token> \
PLURIBUSAI_USER=<yourname> \
./install.sh
```

Restart Claude. See [install/README.md](install/README.md) for status-line notifications.

### Cursor + Grok

```sh
cd install
PLURIBUSAI_ENDPOINT=http://localhost:8787 \
PLURIBUSAI_TOKEN=<your-token> \
PLURIBUSAI_USER=<yourname> \
./install-cursor.sh    # macOS or Windows — toasts + MCP + Grok hook
```

Sets `X-PluribusAI-User` in `~/.cursor/mcp.json` so agents need not repeat your
username. Desktop notifications work on **macOS** (osascript) and **Windows**
(PowerShell toasts). Restart Cursor and Grok after install.

---

## MCP tools

| Tool | Purpose |
|------|---------|
| `send_message` | Broadcast or target a message (`audience`: `"all"` or `["alice"]`) |
| `get_inbox` | Peek at unread messages (never marks read) |
| `read_message` | Mark read for you only |
| `reply_message` | Reply to a thread |
| `get_message` | Full thread + replies + read receipts |
| `list_recent` | Team history, newest first |
| `get_activity` | New messages + replies on your threads (use `cursor` as next `since`) |
| `get_thread_updates` | Threads with unread replies since your last touch |
| `list_teammates` | Usernames seen in the inbox + last activity |
| `search_messages` | Search bodies, refs, and replies |

HTTP: `GET /activity?user=…&since=…&timeout=30` long-polls for the same feed.

### Example prompts

- *"Send a PluribusAI message to all: please review MR …"*
- *"Check my PluribusAI inbox as alice"*
- *"Reply on msg_abc via PluribusAI: looks good, one nit …"*

---

## Local dev (no Docker)

```sh
PLURIBUSAI_STORE=sqlite python3 server.py
# Auth disabled when PLURIBUSAI_TOKEN is unset
```

Tests (stdlib only, no deps):

```sh
python3 tests/test_lifecycle.py
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PLURIBUSAI_TOKEN` | *(unset)* | Bearer token; unset = auth disabled |
| `PLURIBUSAI_HTTP_PORT` | `8787` | HTTP port |
| `PLURIBUSAI_STORE` | `sqlite` | `sqlite` or `postgres` |
| `PLURIBUSAI_DB` | `~/.pluribusai/data/queue.db` | SQLite path |

---

## Repository layout

| Path | What |
|------|------|
| `server.py`, `store.py` | MCP server + storage backends |
| `docker-compose.yml` | One-command self-host |
| `install/` | Client setup, activity poller, SessionStart hook |
| `website/` | Marketing site (GitHub Pages) |
| `docs/` | Protocol, brand, open-core boundary |

---

## Open core

Self-host is **free and full-featured**. Managed cloud adds hosting, SSO, web UI,
and integrations. See [docs/OPEN_CORE.md](docs/OPEN_CORE.md).

---

## License

Apache 2.0 — see [LICENSE](LICENSE).