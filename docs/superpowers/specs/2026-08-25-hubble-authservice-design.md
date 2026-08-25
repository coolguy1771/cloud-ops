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
- Gateway `request.auth.claims` group checks on the same request as Authservice injection (jwt_authn runs before ext_authz header mutation)

## Architecture

```text
Browser → Istio Gateway (hubble.cloud.witl.xyz)
       → AuthorizationPolicy CUSTOM → authservice (OIDC / Authentik session)
       → AuthorizationPolicy ALLOW (host hubble; no claim when)
       → HTTPRoute → hubble-ui.kube-system (ClusterIP)
                    → hubble-relay (in-cluster only)
```

Group membership is enforced by Authentik application policy on app `hubble` (`cloud-ops-admin`). Authservice only admits authenticated sessions.

## Components

| Piece | Location |
|-------|----------|
| Hubble UI + Relay | Cilium HelmRelease (`hubble.ui` / `hubble.relay` enabled) |
| authservice | `kubernetes/apps/authservice/` (Deployment + Service on gRPC 10003) |
| MeshConfig | istiod `extensionProviders.authservice-grpc` |
| HTTPRoute | `hubble` → `hubble-ui:80`, parent Istio Gateway |
| Gateway policies | CUSTOM ExtAuthz for host; ALLOW for host (Authentik policy is group gate) |
| Authentik | OAuth2/OIDC provider + app `hubble`; policy bind to group `cloud-ops-admin`; `groups` scope mapping |
| Secrets | ExternalSecret from vault `cloud-ops` item `hubble-oauth` (`client_id`, `client_secret`) |

## Auth details

- Issuer: `https://auth.cloud.witl.xyz/application/o/hubble/`
- Callback: `https://hubble.cloud.witl.xyz/callback`
- Scopes: `openid`, `profile`, `email`, `groups`
- Group gate: Authentik application policy → `cloud-ops-admin`

## Verification

1. Unauthenticated GET `https://hubble.cloud.witl.xyz` redirects to Authentik
2. User in `cloud-ops-admin` reaches Hubble UI
3. User not in group is denied at Authentik
4. Relay remains ClusterIP-only; no public DNS for relay
