# Hubble UI + Authservice OIDC design

Date: 2026-08-25  
Status: approved  
Scope: Cilium Hubble UI at `hubble.cloud.witl.xyz` behind `istio-ecosystem/authservice` + Authentik; group `cloud-ops-admin` only

## Goal

Expose Hubble UI on the Istio Gateway with browser OIDC login (Authentik), without native app OAuth. Restrict access to Authentik group `cloud-ops-admin`.

## Non-goals

- Public Hubble Relay / metrics API
- Envoy Gateway or oauth2-proxy
- Mesh-wide authservice for every UI (Hubble-only this pass)

## Architecture

```text
Browser → Istio Gateway (hubble.cloud.witl.xyz)
       → AuthorizationPolicy CUSTOM → authservice (OIDC code flow / Authentik)
       → JWT injected → RequestAuthentication + ALLOW (group claim)
       → HTTPRoute → hubble-ui.kube-system (ClusterIP)
                    → hubble-relay (in-cluster only)
```

## Components

| Piece | Location |
|-------|----------|
| Hubble UI + Relay | Cilium HelmRelease (`hubble.ui` / `hubble.relay` enabled) |
| authservice | `kubernetes/apps/authservice/` (Deployment + Service on gRPC 10003) |
| MeshConfig | istiod `extensionProviders.authservice-grpc` |
| HTTPRoute | `hubble` → `hubble-ui:80`, parent Istio Gateway |
| Gateway policies | CUSTOM ExtAuthz for host; ALLOW with JWT + `groups` containing `cloud-ops-admin` |
| Authentik | OAuth2/OIDC provider + app `hubble`; policy bind to group `cloud-ops-admin` |
| Secrets | ExternalSecret from vault `cloud-ops` item `hubble-oauth` (`client_id`, `client_secret`) |

## Auth details

- Issuer: `https://auth.cloud.witl.xyz/application/o/hubble/`
- Callback: `https://hubble.cloud.witl.xyz/callback`
- Scopes: `openid`, `profile`, `email` (groups via Authentik token mapping / userinfo as for Grafana)
- Primary group gate: Authentik application policy → `cloud-ops-admin`
- Defense in depth: Istio `AuthorizationPolicy` `when: request.auth.claims[groups]` includes `cloud-ops-admin`

## Verification

1. Unauthenticated GET `https://hubble.cloud.witl.xyz` redirects to Authentik
2. User in `cloud-ops-admin` reaches Hubble UI
3. User not in group is denied at Authentik and/or gateway
4. Relay remains ClusterIP-only; no public DNS for relay
