# PluribusAI Helm chart

Install the MCP team inbox on Kubernetes.

## Prerequisites

- Kubernetes 1.28+
- Helm 3.12+ (or Helm 4)
- Container image `pluribusai:0.6.0` available to the cluster

### Build and load image (local cluster)

```sh
docker build -t pluribusai:0.6.0 .
# Docker Desktop Kubernetes uses the local daemon — no extra load step.
# kind: kind load docker-image pluribusai:0.6.0
```

## Quick install (SQLite, zero external deps)

```sh
helm upgrade --install pluribusai deploy/helm/pluribusai \
  --namespace pluribusai --create-namespace \
  --set image.pullPolicy=Never \
  --set auth.token="$(openssl rand -hex 24)"
```

Port-forward and verify:

```sh
kubectl port-forward svc/pluribusai 8787:8787 -n pluribusai
curl http://localhost:8787/health
helm test pluribusai -n pluribusai
```

## Postgres (bundled)

```sh
helm upgrade --install pluribusai deploy/helm/pluribusai \
  --namespace pluribusai --create-namespace \
  --set store.type=postgres \
  --set image.pullPolicy=Never \
  --set auth.token="$(openssl rand -hex 24)"
```

## Postgres (external RDS / managed)

```sh
helm upgrade --install pluribusai deploy/helm/pluribusai \
  --set store.type=postgres \
  --set postgresql.enabled=false \
  --set externalDatabase.host=postgres.example.com \
  --set externalDatabase.password='...' \
  --set auth.token='...'
```

## Per-user API keys

```sh
helm upgrade --install pluribusai deploy/helm/pluribusai \
  --set auth.token='' \
  --set-json 'auth.apiKeys={"alice":"pk_xxx","bob":"pk_yyy"}'
```

## Values reference

| Value | Default | Description |
|-------|---------|-------------|
| `store.type` | `sqlite` | `sqlite` or `postgres` |
| `postgresql.enabled` | `true` | Bundled Postgres when `store.type=postgres` |
| `externalDatabase.host` | `""` | External Postgres host (disables bundled) |
| `auth.token` | `""` | Shared bearer token (auto-generated if empty) |
| `auth.apiKeys` | `{}` | Per-user keys map |
| `image.pullPolicy` | `IfNotPresent` | Use `Never` for local images |
| `ingress.enabled` | `false` | Enable ingress |
| `replicaCount` | `1` | Keep at 1 for activity long-poll (see DEPLOY.md) |

See `values.yaml` for the full list.