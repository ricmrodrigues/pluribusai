# PluribusAI Hosted (commercial)

The hosted control plane — OAuth, org management, billing, web dashboard — is
**proprietary** and maintained in a **private repository**, not in this public repo.

This public repository contains only the open protocol, reference server (`server.py`),
and self-host tooling. The OSS data plane can accept JWTs issued by an external
control plane via `PLURIBUSAI_JWT_SECRET` (see `auth.py`).

For the open-core boundary, see [OPEN_CORE.md](OPEN_CORE.md).