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

## Cursor + Grok (no Claude required)

```sh
PLURIBUSAI_ENDPOINT=http://localhost:8787 \
PLURIBUSAI_TOKEN=<token> \
PLURIBUSAI_USER=<yourname> \
./install-cursor.sh
```

Registers Cursor MCP (`~/.cursor/mcp.json` with `X-PluribusAI-User`), Grok
SessionStart hook, and **desktop toasts**:

| Platform | Mechanism |
|----------|-----------|
| macOS | `launchd` + `poll-macos.sh` → `terminal-notifier` (or `osascript` fallback) |
| Windows | Continuous `poll.ps1` daemon + `toast.ps1` → tray balloon (click tray icon) |

**Click a toast (v0.5):** runs `click-handler.py` → writes `~/.pluribusai/focus.json`,
copies an agent-ready prompt to the clipboard, and focuses Cursor (or Grok). Paste
in the agent or start a new session to pick up `focus.json` via SessionStart.

macOS clickable toasts need [terminal-notifier](https://github.com/julienXX/terminal-notifier):
`brew install terminal-notifier`

Also installed automatically by `install.sh` / `install-windows.sh`.
Restart Cursor and Grok after install.

On Windows, Claude Code is optional — `install-windows.sh` and `install-cursor.sh`
configure Cursor and desktop notifications even if `claude` is not in PATH.

## Use it

- *"Send a PluribusAI message to all: …"*
- *"Check my PluribusAI inbox as \<user\>"*
- *"Reply on msg_abc: …"*

## Uninstall

```sh
./install.sh --uninstall          # macOS (Claude + Cursor)
./install-windows.sh --uninstall  # Windows (Claude optional + Cursor)
./install-cursor.sh --uninstall   # Cursor + Grok only
```