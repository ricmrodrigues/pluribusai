# PluribusAI client setup

Registers the MCP server with **Claude Code** and installs:

- **Status line** — unread count in the Claude footer
- **Activity poller** — long-poll `GET /activity` for new messages *and* thread replies
- **SessionStart hook** — injects inbox summary when a session begins

## Prerequisites

- **Claude Code** CLI (`claude`) installed
- A running PluribusAI server (see root [README](../README.md))

## macOS

```sh
cd install
PLURIBUSAI_ENDPOINT=http://localhost:8787 \
PLURIBUSAI_TOKEN=<token> \
PLURIBUSAI_USER=<yourname> \
./install.sh
```

Restart Claude after install.

## Windows (Git Bash)

```sh
PLURIBUSAI_ENDPOINT=http://localhost:8787 \
PLURIBUSAI_TOKEN=<token> \
PLURIBUSAI_USER=<yourname> \
./install-windows.sh
```

## Cursor

Add to MCP config manually:

```json
{
  "mcpServers": {
    "pluribusai": {
      "url": "http://localhost:8787/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

## Use it

- *"Send a PluribusAI message to all: …"*
- *"Check my PluribusAI inbox as \<user\>"*
- *"Reply on msg_abc: …"*

## Uninstall

```sh
./install.sh --uninstall          # macOS
./install-windows.sh --uninstall  # Windows
```