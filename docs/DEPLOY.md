# Deploying PluribusAI (OSS v0.6)

Self-host the MCP team inbox on a VM, Docker, or Kubernetes. This guide covers
production-oriented OSS deployment — not the managed SaaS control plane.

## Quick picks

| Environment | Path |
|-------------|------|
| Local / laptop | `docker compose up -d` (SQLite) |
| Small team VM | `docker compose -f docker-compose.postgres.yml up -d` |
| Kubernetes | `deploy/helm/pluribusai` or `deploy/k8s/` |

## Prerequisites

- Docker 24+ (for compose) or Kubernetes 1.28+
- TLS termination (ingress, reverse proxy, or load balancer)
- Postgres 14+ for multi-user / persistent team hosting

## Auth models

### Shared team token (simple)

Set `PLURIBUSAI_TOKEN` to one long random string. Clients send
`Authorization: Bearer <token>` and identify themselves with `X-PluribusAI-User`.

### Per-user API keys (recommended for shared servers)

Generate keys:

```sh
python3 scripts/gen-api-keys.py alice bob carol > api-keys.json
```

Mount or set:

```sh
export PLURIBUSAI_API_KEYS_FILE=/run/secrets/api-keys.json
```

Each user's bearer token maps to their username. If they send `X-PluribusAI-User`,
it must match the key's user. Per-user keys can coexist with `PLURIBUSAI_TOKEN`
(admin / legacy clients).

## Docker Compose (Postgres)

```sh
cp .env.example .env
# Edit PLURIBUSAI_TOKEN, POSTGRES_PASSWORD
python3 scripts/gen-api-keys.py alice bob > deploy/examples/api-keys.json
docker compose -f docker-compose.postgres.yml up -d --build
curl -s http://localhost:8787/health | jq .
```

## Kubernetes (Helm) — `helm install pluribusai`

See [deploy/helm/pluribusai/README.md](../deploy/helm/pluribusai/README.md).

**Prerequisites:** Kubernetes cluster (Docker Desktop → Settings → Kubernetes → Enable),
Helm 3+, image built locally or pushed to a registry.

```sh
docker build -t pluribusai:0.6.0 .

# SQLite (default) — no Postgres required
helm upgrade --install pluribusai deploy/helm/pluribusai \
  --namespace pluribusai --create-namespace \
  --set image.pullPolicy=Never \
  --set auth.token="$(openssl rand -hex 24)"

kubectl port-forward svc/pluribusai 8787:8787 -n pluribusai
curl http://localhost:8787/health
helm test pluribusai -n pluribusai
```

**Bundled Postgres:**

```sh
helm upgrade --install pluribusai deploy/helm/pluribusai \
  --namespace pluribusai --create-namespace \
  --set store.type=postgres \
  --set image.pullPolicy=Never \
  --set auth.token="$(openssl rand -hex 24)"
```

**External Postgres + registry image:**

```sh
helm upgrade --install pluribusai deploy/helm/pluribusai \
  --set image.repository=your-registry/pluribusai \
  --set store.type=postgres \
  --set postgresql.enabled=false \
  --set externalDatabase.host=postgres.example.com \
  --set externalDatabase.password=secret \
  --set auth.token=your-shared-token \
  --set-json 'auth.apiKeys={"alice":"pk_xxx","bob":"pk_yyy"}' \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=pluribusai.example.com
```

**Windows helper:** `.\scripts\helm-install.ps1` (builds image + installs when kubectl context exists).

Plain manifests (no Helm): see `deploy/k8s/`. Create secrets manually:

```sh
kubectl create secret generic pluribusai-env \
  --from-literal=PGHOST=postgres.example.com \
  --from-literal=PGPASSWORD=... \
  --from-literal=PLURIBUSAI_TOKEN=...
kubectl create secret generic pluribusai-api-keys \
  --from-file=api-keys.json=./api-keys.json
kubectl apply -f deploy/k8s/
```

## Endpoints

| Path | Auth | Purpose |
|------|------|---------|
| `POST /mcp` | Yes | MCP JSON-RPC |
| `GET /activity` | Yes | Long-poll activity feed |
| `GET /health` | No | Liveness / version |
| `GET /metrics` | No | Prometheus text metrics |

Scrape `/metrics` from inside the cluster or restrict via network policy.

## Observability

**Structured logs** (stderr, JSON by default):

```json
{"ts":"2026-06-18T12:00:00.000Z","level":"info","event":"http_request","method":"GET","path":"/activity","status":200,"duration_ms":42.1,"user":"alice","events":1}
```

Set `PLURIBUSAI_LOG_FORMAT=text` for human-readable lines.

**Metrics** (`GET /metrics`): `pluribusai_http_requests_total`,
`pluribusai_activity_longpoll_total`, `pluribusai_uptime_seconds`, etc.

## Activity long-poll and scaling

v0.6 uses an in-process **activity hub**: long-poll waiters wake on writes instead
of polling the database every second.

| Replicas | Recommendation |
|----------|----------------|
| **1** | Default. Long-poll and notifications work out of the box. |
| **2+** | Use **ingress sticky sessions** for `/activity`, **or** set client `timeout=0` (short poll). Cross-replica push is not included in OSS. |

For HA without sticky sessions, configure desktop pollers with shorter timeouts;
they still work, with slightly higher latency.

## Backups

**Postgres:** use your provider's backup (RDS PITR, `pg_dump`, Velero).

**SQLite:** snapshot the volume / copy `queue.db` while stopped.

## Upgrades

1. Back up the database.
2. Deploy the new image (migrations run automatically on startup).
3. Verify `GET /health` returns the new version.
4. Roll client installers if protocol changes (see `docs/PROTOCOL.md`).

## Security checklist

- [ ] TLS on ingress (HTTPS only)
- [ ] Strong `PLURIBUSAI_TOKEN` or per-user keys (not the example file)
- [ ] Postgres password in a secret manager
- [ ] Restrict `/metrics` to monitoring network
- [ ] Do not expose the server without auth on the public internet

## Client install after deploy

Point installers at your hosted URL:

```sh
PLURIBUSAI_ENDPOINT=https://pluribusai.example.com \
PLURIBUSAI_TOKEN=pk_alice_personal_key \
PLURIBUSAI_USER=alice \
./install-cursor.sh
```

Each teammate uses their own key from `api-keys.json`.