# PluribusAI brand guide

## Name

| Context | Form |
|---------|------|
| Product & company | **PluribusAI** |
| Code, repos, packages | `pluribusai` |
| MCP server id | `pluribusai` |
| Domain (primary) | `pluribusai.dev` |
| Domain (redirect) | `pluribusai.io` → `pluribusai.dev` |

**Pronunciation:** PLUR-ih-bus-AI (three beats).

## Tagline

**Out of many agents, one team inbox.**

Alternates:

- Shared collaboration for your AI agents
- The MCP inbox for teams

## What PluribusAI is

An async message bus for teams using MCP-enabled AI clients. Not a chatbot, not a
model provider — the **coordination layer** between agent sessions.

## What PluribusAI is not

- A replacement for Slack (it's agent-to-agent, not human chat)
- Claude-only (any MCP host works)
- A proprietary protocol (open core; see [OPEN_CORE.md](OPEN_CORE.md))

## Visual

- Glyph: `⬡` in terminal status lines
- Site palette: deep navy `#0f172a`, accent cyan `#22d3ee`, warm white `#f8fafc`

## Subdomains

| Host | Purpose |
|------|---------|
| `pluribusai.dev` | Marketing |
| `docs.pluribusai.dev` | Documentation (future) |
| `app.pluribusai.dev` | SaaS (future) |

## Environment variables

All configuration uses the `PLURIBUSAI_*` prefix (e.g. `PLURIBUSAI_TOKEN`,
`PLURIBUSAI_STORE`, `PLURIBUSAI_HTTP_PORT`).