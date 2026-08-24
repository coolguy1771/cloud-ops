# Istio baseline hardening + Kiali (operator) design

Date: 2026-08-24  
Status: draft for review  
Scope: HA/security baseline (option B) + Kiali via operator + Authentik OIDC + Istio Gateway API ingress

## Goal

Apply Istio deployment/security best-practice baselines that fit ambient mode, and expose Kiali on `https://kiali.cloud.witl.xyz` through a new Istio Gateway API ingress in `istio-ingress`, authenticated with Authentik OpenID (Blueprint + 1Password ExternalSecret).

## Non-goals

- Cluster-wide default-deny `AuthorizationPolicy` / waypoint GatewayClass allow-nothing
- Migrating Grafana (or other apps) off Envoy Gateway or Duo OAuth
- Multi-cluster Istio
- Cloudflare tunnel fronting the new Istio ingress (DNS points at the Istio Gateway LoadBalancer)

## Current state

- Istio ambient 1.30.3 under `kubernetes/apps/istio-system/` (base, istiod, cni, ztunnel)
- Single `istiod` replica
- Envoy Gateway in `network` serves existing apps (`*.cloud.witl.xyz`) with TLS secret `cloud-witl-xyz-tls`
- Metrics: Grafana Alloy → Mimir (`http://mimir.mimir-system.svc.cluster.local:8080/prometheus`)
- Authentik at `https://auth.cloud.witl.xyz` (depends on postgres/cert-manager readiness)
- No Kiali; no Authentik blueprints in-repo yet

## Architecture

```
Internet
  -> Hetzner LB (Istio Gateway Service)
    -> Gateway istio-ingress/istio (gatewayClassName: istio)
      -> HTTPRoute (kiali.cloud.witl.xyz)
        -> Service kiali (istio-system)
          -> Kiali Server (managed by Kiali Operator)
            -> Authentik OIDC (auth.cloud.witl.xyz)
            -> Mimir Prometheus API
```

Envoy Gateway remains the ingress for all existing non-Kiali routes.

## 1. Istio control plane HA

Update `istiod` HelmRelease values:

- `autoscaleEnabled: true` (chart default) with `autoscaleMin: 2`
- Pod anti-affinity:
  - required: `topologyKey: kubernetes.io/hostname` for `app=istiod`
  - preferred: `topologyKey: topology.kubernetes.io/zone`

Rationale: Istio deployment best practices; avoids SPOF during drains/rollouts (mutating webhook `failurePolicy: Fail` still matters for some injection paths; ambient still benefits from control-plane HA).

## 2. Security baseline (option B)

### STRICT mTLS

Add mesh-wide `PeerAuthentication` in `istio-system`:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

Ambient ztunnel provides L4 mTLS; STRICT rejects plaintext to mesh workloads. Envoy Gateway / non-mesh traffic paths must keep working (verify after apply).

### Path normalization

Set istiod meshConfig path normalization to the Istio-recommended option for policy safety (DECODE_AND_MERGE_SLASHES unless chart/ambient docs for 1.30.3 prefer another). Document the exact field in the implementation plan from current chart values.

### Explicitly deferred

- Default-deny AuthorizationPolicies
- Waypoint GatewayClass-bound allow-nothing policies

## 3. Istio ingress Gateway (`istio-ingress`)

New Flux-managed namespace/app tree, e.g. `kubernetes/apps/istio-ingress/`:

| Resource | Purpose |
|----------|---------|
| `Namespace` `istio-ingress` | Ingress gateway home |
| `Gateway` `istio` | `gatewayClassName: istio`, HTTPS `:443` |
| TLS Secret | `cloud-witl-xyz-tls` in `istio-ingress` (ExternalSecret import, same 1Password source as `network` certificates/import) |
| DNS | `external-dns` annotations so `kiali.cloud.witl.xyz` (and optional gateway hostname) resolve to the Istio Gateway LoadBalancer |
| Hetzner | Service/Gateway infrastructure annotations as needed for HCloud LB |

Listener notes:

- Protocol HTTPS, port 443
- `allowedRoutes.namespaces.from: All` (or Same + ReferenceGrant if we tighten later)
- `certificateRefs` → local `cloud-witl-xyz-tls`
- Hostname on listener may be `*.cloud.witl.xyz` or omit and filter via HTTPRoute hostnames

Istio creates the dataplane Deployment/Service for this Gateway. Do not route Kiali through `network/envoy`.

## 4. Kiali operator + Kiali CR

Layout under `kubernetes/apps/istio-system/` (or sibling apps with Flux ks wiring):

### Operator

- Helm chart `kiali/kiali-operator` version `2.30.0` (HelmRepository or OCI if available)
- Values: `clusterRoleCreator: true`, `watchNamespace: ""`, allow cluster-wide Kiali installs
- Flux `HelmRelease` with health checks; install CRDs via chart

### Kiali CR (`kiali.io/v1alpha1`)

- Namespace: `istio-system`
- Depends on: operator Ready, istiod Ready, Mimir reachable
- Auth:
  - `strategy: openid`
  - `openid.disable_rbac: true` (Talos API server is not OIDC-integrated)
  - `client_id` + `issuer_uri` from ExternalSecret / CR fields
  - client secret via operator `secret:kiali-openid:...` pattern
  - scopes: `openid`, `profile`, `email`
  - `username_claim`: `email` (or Authentik-preferred claim; finalize in plan)
- `external_services.prometheus.url`: `http://mimir.mimir-system.svc.cluster.local:8080/prometheus`
- `server.web_fqdn`: `kiali.cloud.witl.xyz`, web schema https
- Ambient: Istio root namespace `istio-system`; cluster_wide_access as needed for mesh visibility
- `view_only_mode: true` initially (safer default; can loosen later)

### HTTPRoute

- In `istio-system` (or `istio-ingress`): hostname `kiali.cloud.witl.xyz`
- `parentRefs` → `Gateway/istio` in `istio-ingress`
- Backend: Kiali service port (operator-managed, typically 20001)
- No Envoy `SecurityPolicy` / Duo JWT

## 5. Authentik OIDC (Blueprint + ExternalSecret)

### 1Password + ExternalSecret (pattern A)

- Vault: `cloud-ops`
- Item: `kiali-oauth` with fields `client_id`, `client_secret`, `issuer_url`
- `ExternalSecret` → Secret `kiali-oauth` (and/or `kiali-openid`) for Kiali + Blueprint consumption
- Prerequisite: create the 1Password item before/with first apply (same ops model as `grafana-oauth`)

### Authentik Blueprint (pattern C)

- ConfigMap blueprint mounted via Authentik Helm `blueprints:` (no separate Authentik operator CRD required)
- Defines OAuth2/OIDC Provider + Application for Kiali
- Redirect URI: `https://kiali.cloud.witl.xyz` (Kiali OpenID callback root URL per Kiali docs)
- Issuer URL aligns with Authentik application slug, e.g. `https://auth.cloud.witl.xyz/application/o/kiali/`
- Client id/secret must match the 1Password item (Blueprint uses the same values from Secret/env, or documents one-time generation into 1Password then Blueprint reference)

Authentik must be healthy for Blueprint apply; if postgres/cert-manager chain is still blocked, Kiali can deploy with secrets ready and OIDC login works once Authentik is up.

## 6. Flux / dependency order

1. Istio base → istiod (HA + meshConfig) → cni → ztunnel  
2. PeerAuthentication STRICT  
3. `istio-ingress` namespace + TLS ExternalSecret + Gateway  
4. Kiali operator HelmRelease  
5. Kiali CR + HTTPRoute (depends on operator + Gateway)  
6. Authentik Blueprint ConfigMap (depends on Authentik HelmRelease when ready)

## 7. Verification

- `istiod` Ready replicas ≥ 2 on distinct nodes
- `Gateway/istio` in `istio-ingress` PROGRAMMED with ADDRESS
- `kiali.cloud.witl.xyz` resolves to Istio LB; TLS valid
- Kiali pods Ready; login redirects to Authentik and returns to Kiali
- Mimir metrics visible in Kiali graph (mesh workloads)
- Existing Envoy-fronted apps unchanged
- Smoke: create a non-mesh and mesh pod; STRICT does not break platform ingress

## 8. Risks

| Risk | Mitigation |
|------|------------|
| STRICT mTLS breaks a plaintext client | Roll PeerAuthentication after HA; be ready to set PERMISSIVE temporarily |
| Talos + openid RBAC | `disable_rbac: true` |
| Cert Secret namespace | Import TLS into `istio-ingress`; do not cross-namespace ref without ReferenceGrant |
| Authentik down | Kiali deploys but login fails until IdP/Blueprint ready |
| Extra public LB cost | Expected for dedicated Istio ingress |

## Approval

Pending user review of this file. After approval, create an implementation plan and implement.
