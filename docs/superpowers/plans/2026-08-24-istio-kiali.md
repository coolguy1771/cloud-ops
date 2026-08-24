# Istio Baseline + Kiali Operator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Istio ambient (HA + STRICT mTLS + path normalization) and deploy Kiali via the Kiali operator, exposed on `https://kiali.cloud.witl.xyz` through a new Istio Gateway API ingress in `istio-ingress`, with Authentik OpenID (Blueprint + 1Password ExternalSecret).

**Architecture:** Flux walks `kubernetes/apps/`. Istio stays under `istio-system`. New `istio-ingress` namespace holds an Istio `Gateway` (`gatewayClassName: istio`) plus TLS ExternalSecret. Kiali operator + `Kiali` CR live under `istio-system`. Authentik mounts a Blueprint ConfigMap for the OAuth2 app. Envoy Gateway is unchanged for existing apps.

**Tech Stack:** Istio 1.30.3 (ambient), Gateway API, Kiali operator 2.30.0, Authentik blueprints, External Secrets + 1Password vault `cloud-ops`, Mimir Prometheus API, Flux HelmRelease/Kustomization.

**Spec:** `docs/superpowers/specs/2026-08-24-istio-kiali-design.md`

---

## File map

| Path | Responsibility |
|------|----------------|
| `kubernetes/apps/istio-system/istio/app/istiod-helmrelease.yaml` | HA + meshConfig path normalization |
| `kubernetes/apps/istio-system/istio/app/peerauthentication.yaml` | Mesh-wide STRICT mTLS |
| `kubernetes/apps/istio-system/istio/app/kustomization.yaml` | Include PeerAuthentication |
| `kubernetes/apps/istio-ingress/**` | Namespace, TLS import, Istio Gateway, Flux ks |
| `kubernetes/apps/istio-system/kiali-operator/**` | Operator HelmRepository + HelmRelease |
| `kubernetes/apps/istio-system/kiali/**` | ExternalSecret, Kiali CR, HTTPRoute, Flux ks |
| `kubernetes/apps/istio-system/kustomization.yaml` | Wire operator + kiali ks |
| `kubernetes/apps/authentik/authentik/app/blueprint-kiali.yaml` | Authentik Blueprint ConfigMap |
| `kubernetes/apps/authentik/authentik/app/helmrelease.yaml` | Mount blueprints ConfigMap |
| `kubernetes/apps/authentik/authentik/app/kustomization.yaml` | Include blueprint ConfigMap |
| `AGENTS.md` | Note Istio ingress + Kiali facts |

**Ops prerequisite (human):** Create 1Password item `kiali-oauth` in vault `cloud-ops` with fields `client_id`, `client_secret`, `issuer_url` (e.g. `https://auth.cloud.witl.xyz/application/o/kiali/`) before expecting OIDC login to work.

---

### Task 1: istiod HA + path normalization

**Files:**
- Modify: `kubernetes/apps/istio-system/istio/app/istiod-helmrelease.yaml`

- [ ] **Step 1: Update istiod Helm values**

Replace `spec.values` with:

```yaml
  values:
    profile: ambient
    autoscaleEnabled: true
    autoscaleMin: 2
    autoscaleMax: 5
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
                - key: app
                  operator: In
                  values:
                    - istiod
            topologyKey: kubernetes.io/hostname
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - istiod
              topologyKey: topology.kubernetes.io/zone
    meshConfig:
      pathNormalization:
        normalization: DECODE_AND_MERGE_SLASHES
    pilot:
      env:
        PILOT_ENABLE_AMBIENT_CONTROLLERS: "true"
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/apps/istio-system/istio/app/istiod-helmrelease.yaml
git commit -m "feat(istio): set istiod HA min 2 and path normalization"
```

---

### Task 2: Mesh-wide STRICT PeerAuthentication

**Files:**
- Create: `kubernetes/apps/istio-system/istio/app/peerauthentication.yaml`
- Modify: `kubernetes/apps/istio-system/istio/app/kustomization.yaml`

- [ ] **Step 1: Add PeerAuthentication**

```yaml
---
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT
```

- [ ] **Step 2: Register in kustomization**

Add `- ./peerauthentication.yaml` to `resources` in `kubernetes/apps/istio-system/istio/app/kustomization.yaml`.

- [ ] **Step 3: Commit**

```bash
git add kubernetes/apps/istio-system/istio/app/peerauthentication.yaml \
  kubernetes/apps/istio-system/istio/app/kustomization.yaml
git commit -m "feat(istio): enforce mesh-wide STRICT mTLS"
```

---

### Task 3: `istio-ingress` namespace + TLS ExternalSecret + Gateway

**Files:**
- Create: `kubernetes/apps/istio-ingress/namespace.yaml`
- Create: `kubernetes/apps/istio-ingress/kustomization.yaml`
- Create: `kubernetes/apps/istio-ingress/gateway/ks.yaml`
- Create: `kubernetes/apps/istio-ingress/gateway/app/kustomization.yaml`
- Create: `kubernetes/apps/istio-ingress/gateway/app/externalsecret.yaml`
- Create: `kubernetes/apps/istio-ingress/gateway/app/gateway.yaml`

- [ ] **Step 1: Namespace**

`kubernetes/apps/istio-ingress/namespace.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: istio-ingress
  labels:
    name: istio-ingress
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

- [ ] **Step 2: Root kustomization**

`kubernetes/apps/istio-ingress/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: istio-ingress
resources:
  - ./namespace.yaml
  - ./gateway/ks.yaml
```

- [ ] **Step 3: Flux Kustomization**

`kubernetes/apps/istio-ingress/gateway/ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: istio-ingress-gateway
spec:
  dependsOn:
    - name: istio
      namespace: istio-system
    - name: external-secrets
      namespace: external-secrets
  interval: 1h
  path: ./kubernetes/apps/istio-ingress/gateway/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: istio-ingress
  wait: true
```

- [ ] **Step 4: TLS ExternalSecret (same source as network import)**

`kubernetes/apps/istio-ingress/gateway/app/externalsecret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: cloud-witl-xyz-tls
spec:
  refreshPolicy: CreatedOnce
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: cloud-witl-xyz-tls
    creationPolicy: Orphan
    template:
      type: kubernetes.io/tls
      metadata:
        annotations:
          cert-manager.io/alt-names: "*.cloud.witl.xyz,cloud.witl.xyz"
          cert-manager.io/certificate-name: cloud-witl-xyz
          cert-manager.io/common-name: ""
          cert-manager.io/ip-sans: ""
          cert-manager.io/issuer-group: ""
          cert-manager.io/issuer-kind: ClusterIssuer
          cert-manager.io/issuer-name: letsencrypt-production
          cert-manager.io/uri-sans: ""
        labels:
          controller.cert-manager.io/fao: "true"
  dataFrom:
    - extract:
        key: cloud-witl-xyz-tls
        decodingStrategy: Base64
```

- [ ] **Step 5: Istio Gateway**

`kubernetes/apps/istio-ingress/gateway/app/gateway.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/gateway_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio
  annotations:
    external-dns.alpha.kubernetes.io/hostname: kiali.cloud.witl.xyz
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "kiali.cloud.witl.xyz"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: cloud-witl-xyz-tls
```

If Hetzner LB needs annotations, add under `spec.infrastructure.annotations` (e.g. HCloud load-balancer type) matching patterns used elsewhere once verified against live Service.

- [ ] **Step 6: App kustomization**

`kubernetes/apps/istio-ingress/gateway/app/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml
  - ./gateway.yaml
```

- [ ] **Step 7: Commit**

```bash
git add kubernetes/apps/istio-ingress
git commit -m "feat(istio-ingress): add Istio Gateway API ingress and TLS"
```

---

### Task 4: Kiali operator

**Files:**
- Create: `kubernetes/apps/istio-system/kiali-operator/ks.yaml`
- Create: `kubernetes/apps/istio-system/kiali-operator/app/helmrepository.yaml`
- Create: `kubernetes/apps/istio-system/kiali-operator/app/helmrelease.yaml`
- Create: `kubernetes/apps/istio-system/kiali-operator/app/kustomization.yaml`
- Modify: `kubernetes/apps/istio-system/kustomization.yaml`

- [ ] **Step 1: HelmRepository**

`kubernetes/apps/istio-system/kiali-operator/app/helmrepository.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: kiali
spec:
  interval: 1h
  url: https://kiali.org/helm-charts
```

- [ ] **Step 2: HelmRelease**

`kubernetes/apps/istio-system/kiali-operator/app/helmrelease.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kiali-operator
spec:
  interval: 1h
  chart:
    spec:
      chart: kiali-operator
      version: "2.30.0"
      sourceRef:
        kind: HelmRepository
        name: kiali
  install:
    crds: CreateReplace
    remediation:
      retries: -1
  upgrade:
    crds: CreateReplace
    cleanupOnFail: true
    remediation:
      retries: 3
  values:
    cr:
      create: false
    watchNamespace: ""
    clusterRoleCreator: true
    allowAllAccessibleNamespaces: true
```

- [ ] **Step 3: App kustomization + Flux ks**

`kubernetes/apps/istio-system/kiali-operator/app/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./helmrepository.yaml
  - ./helmrelease.yaml
```

`kubernetes/apps/istio-system/kiali-operator/ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: kiali-operator
spec:
  dependsOn:
    - name: istio
      namespace: istio-system
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: kiali-operator
      namespace: istio-system
  interval: 1h
  path: ./kubernetes/apps/istio-system/kiali-operator/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: istio-system
  wait: true
```

- [ ] **Step 4: Wire into istio-system root**

Update `kubernetes/apps/istio-system/kustomization.yaml` resources to:

```yaml
resources:
  - ./namespace.yaml
  - ./istio/ks.yaml
  - ./kiali-operator/ks.yaml
  - ./kiali/ks.yaml
```

(Include `./kiali/ks.yaml` only after Task 5 files exist; if committing per-task, add operator first then kiali in Task 5.)

- [ ] **Step 5: Commit**

```bash
git add kubernetes/apps/istio-system/kiali-operator \
  kubernetes/apps/istio-system/kustomization.yaml
git commit -m "feat(kiali): install Kiali operator via Flux"
```

---

### Task 5: Kiali CR + OIDC ExternalSecret + HTTPRoute

**Files:**
- Create: `kubernetes/apps/istio-system/kiali/ks.yaml`
- Create: `kubernetes/apps/istio-system/kiali/app/externalsecret.yaml`
- Create: `kubernetes/apps/istio-system/kiali/app/kiali.yaml`
- Create: `kubernetes/apps/istio-system/kiali/app/httproute.yaml`
- Create: `kubernetes/apps/istio-system/kiali/app/kustomization.yaml`
- Modify: `kubernetes/apps/istio-system/kustomization.yaml` (ensure `./kiali/ks.yaml` listed)

- [ ] **Step 1: ExternalSecret for OIDC**

`kubernetes/apps/istio-system/kiali/app/externalsecret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: kiali-oauth
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: kiali
    template:
      engineVersion: v2
      data:
        oidc-secret: "{{ .client_secret }}"
        client-id: "{{ .client_id }}"
        issuer-url: "{{ .issuer_url }}"
  dataFrom:
    - extract:
        key: kiali-oauth
```

Kiali OpenID expects the client secret in a Secret named `kiali` with key `oidc-secret` (operator convention).

- [ ] **Step 2: Kiali CR**

`kubernetes/apps/istio-system/kiali/app/kiali.yaml`:

```yaml
---
apiVersion: kiali.io/v1alpha1
kind: Kiali
metadata:
  name: kiali
  namespace: istio-system
spec:
  auth:
    strategy: openid
    openid:
      client_id: "kiali"
      disable_rbac: true
      issuer_uri: "https://auth.cloud.witl.xyz/application/o/kiali/"
      scopes:
        - openid
        - profile
        - email
      username_claim: email
  deployment:
    cluster_wide_access: true
    view_only_mode: true
    accessible_namespaces:
      - "**"
  external_services:
    istio:
      root_namespace: istio-system
    prometheus:
      url: http://mimir.mimir-system.svc.cluster.local:8080/prometheus
  server:
    web_fqdn: kiali.cloud.witl.xyz
    web_schema: https
    web_port: 443
```

Note: If the Authentik application slug differs, update `issuer_uri` and 1Password `issuer_url` together. Prefer reading `client_id` from the Secret via a follow-up if the operator supports `secret:` refs for client_id; otherwise keep CR client_id aligned with the 1Password `client_id` value (`kiali`).

- [ ] **Step 3: HTTPRoute to Istio Gateway**

`kubernetes/apps/istio-system/kiali/app/httproute.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kiali
  annotations:
    external-dns.alpha.kubernetes.io/hostname: kiali.cloud.witl.xyz
spec:
  parentRefs:
    - name: istio
      namespace: istio-ingress
      sectionName: https
  hostnames:
    - kiali.cloud.witl.xyz
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: kiali
          port: 20001
```

- [ ] **Step 4: App kustomization + Flux ks**

`kubernetes/apps/istio-system/kiali/app/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml
  - ./kiali.yaml
  - ./httproute.yaml
```

`kubernetes/apps/istio-system/kiali/ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: kiali
spec:
  dependsOn:
    - name: kiali-operator
      namespace: istio-system
    - name: istio-ingress-gateway
      namespace: istio-ingress
    - name: mimir
      namespace: mimir-system
  interval: 1h
  path: ./kubernetes/apps/istio-system/kiali/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: istio-system
  wait: true
```

Ensure root `kubernetes/apps/istio-system/kustomization.yaml` lists `./kiali/ks.yaml`.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/apps/istio-system/kiali \
  kubernetes/apps/istio-system/kustomization.yaml
git commit -m "feat(kiali): add Kiali CR, OIDC secret, and Istio HTTPRoute"
```

---

### Task 6: Authentik Blueprint for Kiali OIDC

**Files:**
- Create: `kubernetes/apps/authentik/authentik/app/blueprint-kiali.yaml`
- Modify: `kubernetes/apps/authentik/authentik/app/helmrelease.yaml`
- Modify: `kubernetes/apps/authentik/authentik/app/kustomization.yaml`

- [ ] **Step 1: Blueprint ConfigMap**

`kubernetes/apps/authentik/authentik/app/blueprint-kiali.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: authentik-blueprint-kiali
data:
  kiali.yaml: |
    version: 1
    metadata:
      name: kiali-oauth
    entries:
      - model: authentik_providers_oauth2.oauth2provider
        id: kiali-provider
        state: present
        identifiers:
          name: Kiali
        attrs:
          name: Kiali
          client_type: confidential
          client_id: kiali
          # Set client_secret in Authentik UI or via blueprint attrs to match 1Password kiali-oauth.
          # After first apply, copy the provider secret into 1Password item kiali-oauth.
          redirect_uris:
            - matching_mode: strict
              url: https://kiali.cloud.witl.xyz/
            - matching_mode: strict
              url: https://kiali.cloud.witl.xyz
          sub_mode: user_email
          include_claims_in_id_token: true
          issuer_mode: per_provider
      - model: authentik_core.application
        id: kiali-app
        state: present
        identifiers:
          slug: kiali
        attrs:
          name: Kiali
          slug: kiali
          policy_engine_mode: any
          provider: !KeyOf kiali-provider
```

If Authentik requires an authorization flow reference, add `authorization_flow` / `authentication_flow` via `!Find` against default flows (discover exact flow slugs from a healthy Authentik instance during implement and patch the blueprint).

- [ ] **Step 2: Mount blueprint in Authentik HelmRelease**

Add under `spec.values`:

```yaml
    blueprints:
      configMaps:
        - authentik-blueprint-kiali
```

- [ ] **Step 3: Register ConfigMap in authentik app kustomization**

Add `- ./blueprint-kiali.yaml` to resources.

- [ ] **Step 4: Commit**

```bash
git add kubernetes/apps/authentik/authentik/app/blueprint-kiali.yaml \
  kubernetes/apps/authentik/authentik/app/helmrelease.yaml \
  kubernetes/apps/authentik/authentik/app/kustomization.yaml
git commit -m "feat(authentik): add Kiali OAuth2 blueprint"
```

---

### Task 7: AGENTS.md + verify

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update workspace facts**

Add/adjust bullets:
- Istio ingress Gateway lives in `istio-ingress` (`gatewayClassName: istio`); Kiali is exposed there, not via Envoy.
- Kiali operator + CR in `istio-system`; OIDC via Authentik (`kiali-oauth` 1Password item).
- istiod `autoscaleMin: 2`; mesh PeerAuthentication STRICT; path normalization DECODE_AND_MERGE_SLASHES.

- [ ] **Step 2: Push and reconcile (when ready to deploy)**

```bash
git push
flux reconcile source git flux-system -n flux-system
flux reconcile ks istio -n istio-system --with-source
flux reconcile ks istio-ingress-gateway -n istio-ingress --with-source
flux reconcile ks kiali-operator -n istio-system --with-source
flux reconcile ks kiali -n istio-system --with-source
```

- [ ] **Step 3: Verify**

```bash
kubectl get deploy -n istio-system istiod
kubectl get peerauthentication -n istio-system default -o yaml
kubectl get gateway -n istio-ingress istio
kubectl get pods -n istio-system -l app=kiali
kubectl get httproute -n istio-system kiali
curl -sI https://kiali.cloud.witl.xyz | head
```

Expected: istiod ≥2 ready on different nodes; Gateway PROGRAMMED with ADDRESS; Kiali pods Ready; HTTPS responds (OIDC redirect once Authentik + 1Password item exist).

- [ ] **Step 4: Commit AGENTS.md**

```bash
git add AGENTS.md
git commit -m "docs(agents): record Istio ingress and Kiali facts"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| istiod autoscaleMin 2 + anti-affinity | Task 1 |
| Path normalization | Task 1 |
| STRICT PeerAuthentication | Task 2 |
| istio-ingress Gateway + TLS + DNS | Task 3 |
| Kiali operator 2.30.0 | Task 4 |
| Kiali CR openid + Mimir + view_only | Task 5 |
| HTTPRoute → Istio Gateway | Task 5 |
| Authentik Blueprint + Helm mount | Task 6 |
| 1Password ExternalSecret kiali-oauth | Task 5 |
| Envoy unchanged | (no Envoy edits) |
| Default-deny authz deferred | (omitted) |
| Verification | Task 7 |

## Placeholder scan

None intentional. Authentik flow `!Find` slugs may need a one-line adjust during Task 6 against a live Authentik; client_secret sync is an explicit ops step documented above.
