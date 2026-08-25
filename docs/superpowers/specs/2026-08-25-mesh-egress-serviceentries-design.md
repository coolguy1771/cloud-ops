# Mesh egress ServiceEntries design

Date: 2026-08-25
Status: approved / implemented
Scope: Register known external HTTPS/TLS destinations in the Istio ambient service registry

## Goal

Add Istio `ServiceEntry` resources for cluster workloads' known outbound hosts so they appear in the mesh registry (Kiali/telemetry) and are ready if egress policy tightens later (`REGISTRY_ONLY`).

## Non-goals

- Egress `DestinationRule` / outlier detection on external hosts
- Switching mesh `outboundTrafficPolicy` to `REGISTRY_ONLY`
- Cloudflare Tunnel edge (connects by edge IP; hostname SE is a poor fit)
- Omni API (`*.omni.siderolabs.io`) — Terraform/`omnictl` off-cluster; no in-cluster Omni client today
- Hetzner Cloud API — `hcloud-ccm` / CSI run in `kube-system`, which is not ambient
- Image-pull registries used only by the container runtime (node path), except Flux OCI (`ghcr.io`) which source-controller fetches over HTTPS

## Placement

Central catalog under the existing ambient `network` namespace:

```
kubernetes/apps/network/mesh-egress/
  secrets/
    kustomization.yaml
    externalsecret.yaml   # → Secret cloudflare-account-id-secret
  secrets-ks.yaml         # Flux: mesh-egress-secrets (wait for Secret)
  app/
    kustomization.yaml
    serviceentries.yaml   # tempo-r2 host uses ${CLOUDFLARE_ACCOUNT_ID}
  ks.yaml                 # Flux: mesh-egress (postBuild.substituteFrom)
```

- Flux `mesh-egress-secrets` then `mesh-egress` (`dependsOn` + `postBuild.substituteFrom`)
- Root `kubernetes/apps/network/kustomization.yaml` includes both `secrets-ks.yaml` and `ks.yaml`
- Each `ServiceEntry` uses `exportTo: ["*"]` so ambient namespaces can resolve hosts
- Do not duplicate object-storage entries next to Loki/Mimir/Tempo apps
- R2 hostname is never committed; Flux substitutes `${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com` (same pattern as CNPG ObjectStore)

## ServiceEntry shape

Shared defaults for every entry:

- `location: MESH_EXTERNAL`
- `resolution: DNS` (concrete hosts only; no wildcards)
- `exportTo: ["*"]`
- Port `443`, name `https`, protocol `TLS` (apps terminate TLS; passthrough)

## Host inventory

| ServiceEntry name | Hosts | Primary callers |
|-------------------|-------|-----------------|
| `tigris-storage` | `t3.storage.dev` | Loki, Mimir |
| `tempo-r2` | `${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com` | Tempo R2; Flux postBuild from `cloudflare-account-id-secret` (ESO ← 1Password `cloudflare.account_tag`) |
| `github` | `github.com`, `ghcr.io` | Flux GitRepository + OCIRepository |
| `letsencrypt` | `acme-v02.api.letsencrypt.org` | cert-manager ACME |
| `cloudflare-api` | `api.cloudflare.com` | external-dns, cert-manager DNS-01 |
| `onepassword` | `my.1password.com`, `events.1password.com` | 1Password Connect Sync (ESO talks to in-cluster Connect) |

## Out of scope follow-ups

- Add Omni / Hetzner SEs if those clients move into ambient namespaces
- Expand 1Password hosts if Sync fails against another regional endpoint
- Add `raw.githubusercontent.com` if Grafana/Flux dashboard fetches need registry visibility
- Tunnel / QUIC edge registration if tunnel observability becomes a goal

## Verification

1. Flux reconciles `mesh-egress`; `kubectl -n network get serviceentry` lists the six entries
2. Ambient callers still reach Tigris, R2, GitHub, LE, Cloudflare, 1Password Sync (no regressions)
3. Kiali (or `istioctl proxy-config` / ztunnel workload view) shows the external hosts as registered services
