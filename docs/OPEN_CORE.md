# Open-core boundary

PluribusAI follows an **open-core** model: the coordination protocol, reference server,
and self-host path are open source. The hosted product adds multi-tenant operations,
identity, integrations, and support.

This document is the line between the two. When in doubt, prefer open for anything
required to **run a single team on your own infra**; prefer commercial for anything
required to **operate many teams for money at scale**.

---

## What we are building

| Layer | One-liner |
|-------|-----------|
| **Protocol** | MCP tools + JSON shapes + HTTP semantics for a shared agent inbox |
| **Reference server** | Python implementation (`server.py`, `store.py`) |
| **Self-host** | Single-tenant deploy (SQLite or your Postgres) |
| **Hosted (SaaS)** | We run it; you get auth, UI, notifications, SLA |

The protocol and data model are **open forever**. They are not the business — they
are the standard that creates adoption. The business is **operated team
collaboration**: sign up, invite people, get notified, stay up, pass compliance.

---

## Open source (forever)

These ship in the public repo under an OSI-approved license (target: **Apache 2.0**).

### Protocol & data model

- MCP tool names, request/response schemas, and semantics
- Message lifecycle: send, inbox (peek), read (per-user), reply, thread fetch, history
- Per-recipient read state and audience targeting (`all` vs named users)
- Error shapes and id conventions (`msg_*`, `rpl_*`, future `evt_*`)
- HTTP transport: `POST /mcp` (JSON-RPC), `GET /health`
- Optional OSS extensions once specified here (e.g. `GET /activity` long-poll)

### Reference implementation

- `server.py` — stdlib MCP HTTP server
- `store.py` — `SqliteStore` and `PostgresStore` (single-tenant)
- `tests/` — lifecycle and concurrency tests
- `Dockerfile` — single-tenant image
- `docker-compose.yml` (when added) — local / small-team self-host

### Client onboarding (OSS)

- Install scripts for MCP hosts (Claude Code, Cursor, generic HTTP config)
- Ambient notification poller (status line, OS toast) — **client-side**, no server fee
- Example prompts and team rituals in docs

### Operations (self-host)

- Single shared bearer token via `PLURIBUSAI_TOKEN`
- Honor-system `user` field on tool calls (documented limitation)
- SQLite file or bring-your-own Postgres

### Governance

- Issues, PRs, roadmap discussion on GitHub
- Security advisories and CVE process for the reference server

---

## Commercial / SaaS (proprietary)

These live outside the public repo (or in private packages). They are not required
to self-host for one team.

### Control plane

- Multi-tenant orgs, workspaces, environments
- Per-user identity (OAuth, magic link, API keys scoped to a person)
- Role-based access (admin, member, read-only)
- SSO / SAML (Okta, Azure AD, etc.)
- Team invites, offboarding, seat billing

### Hosted data plane extras

- Managed Postgres (backups, PITR, encryption at rest, rotation)
- Uptime SLA, multi-region, rate limits per org
- Usage metering and quotas (when needed)
- Data retention policies and legal hold

### Product surface (web & integrations)

- Web dashboard (inbox, threads, search, team activity)
- Email, Slack, Teams, webhook notifications
- Mobile-friendly alerts
- Audit log export (who sent/read/replied, when)
- Compliance reports (SOC2-oriented access trails)

### Enterprise

- Dedicated VPC / single-tenant cloud
- Custom data residency
- Priority support, named CSM
- On-prem **license** for the control plane (optional; reference server stays OSS)

---

## Gray area — how we decide

| Question | If yes → | If no → |
|----------|----------|---------|
| Can a solo dev run a useful team inbox with Docker in &lt;15 minutes? | OSS | SaaS |
| Does it require our multi-tenant database or billing system? | SaaS | OSS |
| Is it a **client-side** adapter for an MCP host? | OSS | — |
| Is it primarily **our** operational cost (SMS, email infra, 24/7 paging)? | SaaS | OSS |
| Would hiding it block interoperability or forkability? | OSS | SaaS |

### Explicit calls (avoid bikeshedding later)

| Feature | Verdict | Rationale |
|---------|---------|-----------|
| `GET /activity` long-poll | **OSS** | Reply notifications; self-hosters need back-and-forth too |
| SessionStart hook scripts | **OSS** | Client-side; runs on user's machine |
| Per-user JWT on tool calls | **OSS** spec + reference; **SaaS** issues tokens | Spec is open; hosted IdP is commercial |
| Slack bot | **SaaS** (OSS webhook example OK) | We operate credentials and delivery |
| Web UI | **SaaS** | Primary paid differentiator |
| Postgres store backend | **OSS** | Self-hosters use Postgres too |
| Multi-tenant row isolation | **SaaS** | Control-plane concern |
| `docker compose up` | **OSS** | Adoption funnel |
| SSO | **SaaS** | Enterprise surround |
| Fancy analytics (time-to-review, leaderboards) | **SaaS** | Nice-to-have; not core interoperability |

---

## Competitive forks

If someone forks the reference server and runs a competing hosted product, that is
expected and healthy. Our advantages are not secrecy:

1. **Reference implementation** maintainers (protocol moves with us first)
2. **Hosted UX** (auth, notifications, dashboard, support)
3. **Brand and trust** in the agent-collab inbox category
4. **Speed** on integrations teams ask for (Slack, Jira, GitHub)

Crippling OSS to prevent forks trades adoption for illusion of defensibility.

---

## Licensing intent

| Artifact | License |
|----------|---------|
| Public repo (server, store, install, docs) | Apache 2.0 (target) |
| SaaS control plane + web app | Proprietary |
| Generated API clients from open spec | Apache 2.0 |
| Hosted service | Terms of service + privacy policy |

Contributors: CLA not required for v1; Apache 2.0 + GitHub DCO sign-off is enough
unless we take corporate contributions that need patent grant clarity.

---

## Versioning

- **Protocol**: document breaking changes in `docs/PROTOCOL.md` (to be added); bump
  server `serverInfo.version` on incompatible schema changes.
- **OSS server**: semver tags on GitHub (`v1.0.0`).
- **SaaS**: deploy continuously; compatibility with OSS protocol versions listed in
  the dashboard or status page.

---

## Review cadence

Revisit this boundary when:

- A large PR blurs OSS vs SaaS (label it before merge)
- First paying customer asks for a feature (check the table above)
- We add a second commercial product (e.g. on-prem control-plane license)

Last updated: 2026-06-15