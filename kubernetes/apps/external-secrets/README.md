# External Secrets Operator

Synchronize secrets from external secret management systems into Kubernetes.

## Overview

External Secrets Operator (ESO) syncs secrets from 1Password (via SDK) into Kubernetes Secrets. This enables GitOps-friendly secret management without storing secrets in Git.

## Architecture

```
1Password Vault
    |
1Password SDK (via Service Account)
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
- Prometheus metrics
- Client-side caching

### onepassword (SDK)

Uses 1Password SDK with a Service Account for direct API access. No Connect Server required.

**Benefits**:
- Simpler setup (no server deployment)
- Direct API access via service account
- Built-in caching support

## ClusterSecretStore

The `onepassword` ClusterSecretStore provides cluster-wide access to a 1Password vault.

**Configuration**:
- Provider: `onepasswordSDK`
- Auth: Service Account token
- Cache: 5m TTL, 100 max entries

## Setup

### 1. Create a 1Password Service Account

1. In 1Password, go to **Developer** > **Service Accounts**
2. Create a new Service Account
3. Grant access to your vault (e.g., "Kubernetes")
4. Copy the service account token (starts with `ops_`)

### 2. Create the Secret

```bash
kubectl create secret generic onepassword-service-account \
  --from-literal=token=ops_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -n external-secrets
```

### 3. Update Vault Name

Edit `onepassword/app/clustersecretstore.yaml` to set your vault name:

```yaml
spec:
  provider:
    onepasswordSDK:
      vault: YourVaultName
```

### 4. Organize Secrets in 1Password

Create items in your vault with fields that match your ExternalSecret references.

**Example: Cloudflare DNS Token**
- Item name: `cloudflare`
- Field name: `CLOUDFLARE_DNS_TOKEN`
- Field value: your-api-token

## Using ExternalSecrets

The SDK uses the format `<item>/<field>` for secret references.

### Basic Example

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: my-kubernetes-secret
    creationPolicy: Owner
  data:
    - secretKey: API_KEY
      remoteRef:
        key: my-item/api_key
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
    name: onepassword
  target:
    name: database-url
    template:
      engineVersion: v2
      data:
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@{{ .host }}/{{ .database }}"
  data:
    - secretKey: username
      remoteRef:
        key: postgres/username
    - secretKey: password
      remoteRef:
        key: postgres/password
    - secretKey: host
      remoteRef:
        key: postgres/host
    - secretKey: database
      remoteRef:
        key: postgres/database
```

## Required 1Password Items

Based on the ExternalSecret resources, create these items in your vault:

| Item Name | Fields |
|-----------|--------|
| `cloudflare` | `CLOUDFLARE_DNS_TOKEN` |
| `external-dns-aws-roles-anywhere` | `trust_anchor_arn`, `profile_arn`, `role_arn`, `aws_region`, `certificate`, `private_key` |
| `mimir-s3-config` | `s3_endpoint`, `s3_access_key_id`, `s3_secret_access_key`, `mimir_bucket` |
| `mimir-oidc-config` | `client_id`, `client_secret` |
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
kubectl describe clustersecretstore onepassword
```

### View Operator Logs

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Common Issues

**"found multiple labels with the same key"**
- Ensure each field in your 1Password item has a unique label name

**Secret not syncing**
- Verify the item/field path matches exactly (case-sensitive)
- Check service account has access to the vault

## References

- [External Secrets Operator](https://external-secrets.io/)
- [1Password SDK Provider](https://external-secrets.io/latest/provider/1password-sdk/)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
