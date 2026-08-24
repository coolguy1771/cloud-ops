# External Secrets Operator

Synchronize secrets from external secret management systems into Kubernetes.

## Overview

External Secrets Operator (ESO) syncs secrets from 1Password Connect into Kubernetes Secrets. This enables GitOps-friendly secret management without storing secrets in Git.

## Architecture

```
1Password Vault
    |
1Password Connect (API + Sync)
    |
External Secrets Operator
    |
Kubernetes Secrets
```

## Components

### external-secrets

Core operator that watches ExternalSecret resources and syncs them.

**Features**:
- Automatic secret refresh (default: 1h)
- Multiple secret backend support
- Template engine for secret transformation
- Prometheus metrics and Grafana dashboard
- Client-side caching

### onepassword-connect

Deploys 1Password Connect using the official Helm chart.

**Benefits**:
- Supported Connect Server deployment
- ServiceMonitor for Prometheus
- Credentials managed via ExternalSecret after bootstrap

## ClusterSecretStore

The `onepassword-connect` ClusterSecretStore provides cluster-wide access to a 1Password vault.

**Configuration**:
- Provider: `onepassword` (Connect)
- Auth: Connect token from `onepassword-connect-vault-secret`
- Vault: `cloud-ops`

## Setup

### 1. Create 1Password Connect Credentials

Create a 1Password item named `1password` in the `cloud-ops` vault with:

| Field | Description |
|-------|-------------|
| `OP_CREDENTIALS_JSON` | Base64-encoded Connect credentials JSON |
| `OP_CONNECT_TOKEN` | Connect server access token |

### 2. Bootstrap Secrets

During cluster bootstrap, credentials are injected via 1Password CLI into:

- `onepassword-connect-credentials-secret`
- `onepassword-connect-vault-secret`

### 3. Organize Secrets in 1Password

Create items in your vault with fields that match your ExternalSecret references.

**Example: Cloudflare DNS Token**
- Item name: `cloudflare`
- Field name: `CLOUDFLARE_DNS_TOKEN`
- Field value: your-api-token

## Using ExternalSecrets

Use `dataFrom.extract` with templates for Connect-backed secrets.

### Basic Example

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: my-kubernetes-secret
    template:
      data:
        API_KEY: "{{ .API_KEY }}"
  dataFrom:
    - extract:
        key: my-item
```

### With Template

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: database-url
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: database-url
    template:
      engineVersion: v2
      data:
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@{{ .host }}/{{ .database }}"
  dataFrom:
    - extract:
        key: postgres
```

## Required 1Password Items

Based on the ExternalSecret resources, create these items in your vault:

| Item Name | Fields |
|-----------|--------|
| `cloudflare` | `CLOUDFLARE_DNS_TOKEN` |
| `external-dns-aws-roles-anywhere` | `trust_anchor_arn`, `profile_arn`, `role_arn`, `aws_region`, `certificate`, `private_key` |
| `grafana-datasource-org` | `org-id` (named tenant for Alloy/istiod/Kiali; `witl-xyz` is shared by the home-ops and cloud-ops clusters) |
| `observability-m2m` | Platform M2M (`client_id`, `client_secret`); JWT `tenant_id` defaults to `witl-xyz` |
| `observability-m2m-<tenant>` | Extra tenant M2M (`client_id`, `username`, `password`, `tenant-id`); e.g. `observability-m2m-icbplays-net` for `*.icbplays.net` |
| `mimir` | `s3_endpoint`, `s3_access_key_id`, `s3_secret_access_key`, `mimir_bucket` |
| `flux` | `FLUX_GITHUB_APP_PRIVATE_KEY` |

## Troubleshooting

### Check ExternalSecret Status

```bash
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>
```

### Check ClusterSecretStore Status

```bash
kubectl get clustersecretstore
kubectl describe clustersecretstore onepassword-connect
```

### View Operator Logs

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Common Issues

**Secret not syncing**
- Verify the item name matches exactly (case-sensitive)
- Check Connect token has access to the vault

**Connect credentials invalid**
- Ensure `OP_CREDENTIALS_JSON` is base64-encoded in 1Password
- The credentials ExternalSecret uses `b64dec` in its template

## References

- [External Secrets Operator](https://external-secrets.io/)
- [1Password Connect Provider](https://external-secrets.io/latest/provider/1password/)
- [1Password Connect Helm Chart](https://github.com/1Password/connect-helm-charts)
