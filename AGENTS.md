## Learned User Preferences

- Port platform patterns from `coolguy1771/home-ops` or `onedr0p/home-ops`, adapting cloud-ops-specific names (repo URL, vault, scale set) instead of copying upstream identifiers verbatim.
- Manage Omni cluster lifecycle with Terraform (`siderolabs/omni` provider); do not use `omnictl cluster template sync` or manual Omni UI edits for resources Terraform owns.
- Merge non-major Renovate PRs in `coolguy1771/cloud-ops` and `coolguy1771/home-ops` when CI is clean; skip `type/major` PRs and PRs with failing checks.
- When porting external-secrets from home-ops, keep the `cloud-ops` 1Password vault name and `onepassword-connect` ClusterSecretStore naming.
- Prefer Flux walking `kubernetes/apps/` directories over maintaining a root `kubernetes/apps/kustomization.yaml`.
- Prefer Hetzner CCM LoadBalancer annotations for Istio ingress over Cloudflare Tunnel (`cloudflared`); Cloudflare proxy on DNS is fine.
- Do not pass repeated `--gateway-name` flags to external-dns (only the last value is kept); omit gateway-name filters so all Gateway API HTTPRoutes are watched.
- Grafana uses Authentik OAuth (not Duo); home-ops has no local Grafana—dashboards and human queries use cloud Grafana.

## Learned Workspace Facts

- GitOps repo for Talos cluster `cloud-ops` on Hetzner Cloud: Flux reconciles `kubernetes/`, Helmfile bootstraps via `bootstrap/helmfile/`.
- GitHub repos: `coolguy1771/cloud-ops` (this repo), `coolguy1771/home-ops` (reference fork of onedr0p patterns).
- Networking: kube-proxy disabled; Cilium full KPR via KubePrism:7445 (Talos 1.13 inline patches); tuned for Istio ambient (`cni.exclusive: false`, `socketLB.hostNamespaceOnly: true`, `bpf.masquerade: false`, `envoy.enabled: false`); app namespaces label `istio.io/dataplane-mode: ambient`.
- Istio ambient is Flux-managed under `kubernetes/apps/istio-system/` (base, istiod, cni, ztunnel, kiali operator); Helm charts use `oci://gcr.io/istio-release/charts/{base,istiod,cni,ztunnel}` (not image repos under `oci://gcr.io/istio-release/{...}`); istiod `autoscaleMin: 2`; mesh PeerAuthentication STRICT; path normalization `DECODE_AND_MERGE_SLASHES`; primary ingress is Istio Gateway in `istio-ingress` (`gatewayClassName: istio`, listener `*.cloud.witl.xyz`, Hetzner CCM); per-host Gateway `AuthorizationPolicy`s + shared `RequestAuthentication` (HTTPRoute `targetRefs` not supported yet on Istio 1.30); gateway EnvoyFilter hardening (conn limit + local rate limit); PodMonitor on gateway pods; ambient waypoints (`istio-waypoint`) in `observability`, `mimir-system`, `authentik` via `istio.io/use-waypoint: waypoint`; Envoy Gateway removed; Cloudflare Tunnel kept but disabled (`replicas: 0`).
- external-dns (`cloudflare-dns`) sources include `gateway-httproute` and `crd` without `--gateway-name` filters so Istio Gateway HTTPRoutes get Cloudflare-proxied DNS to the Hetzner LB.
- Central observability on cloud-ops (`kubernetes/apps/observability/`, `mimir-system/`): Grafana, Mimir, Loki, Tempo at `*.cloud.witl.xyz`; home-ops ships metrics/logs/traces via `observability-m2m` OAuth client credentials to tenant `witl-xyz`.
- Observability multi-tenancy uses named `X-Scope-OrgID` tenants (not OIDC sub): default `witl-xyz` (home-ops + cloud-ops), `icbplays-net` for `*.icbplays.net`, extra slugs supported; Grafana/M2M JWTs carry `tenant_id`; ingress maps to org header; override per user with Authentik attribute `observability_tenant`.
- CI/CD workflows: `tag`, `flux-local`, `renovate`, `label-sync`; `tag` was ported from home-ops.
- Self-hosted runners use ARC v2 (`gha-runner-scale-set-controller` / `gha-runner-scale-set`) with scale set `cloud-ops-runner` (0-3) in `actions-runner-system`, targeting `github.com/coolguy1771/cloud-ops`; runner container sets `securityContext.allowPrivilegeEscalation: false`.
- Omni Terraform in `infrastructure/terraform/` (provider `siderolabs/omni` v0.1.0-alpha.3; `omni_config_patch` in `omni_patches.tf`; auth `OMNI_SERVICE_ACCOUNT_KEY`); import existing cluster with `infrastructure/terraform/scripts/import-omni.sh` before first apply; machine sets `cloud-ops-control-planes` and `cloud-ops-workers`.
- Control planes are static `hcloud_server` with explicit Omni node assignment; workers use Hetzner Omni infra provider MachineClasses (`hetzner_infra_provider.tf` / `coolguy1771/hetzner-infra-provider`).
- Cloudflare WAF/IP Access for Authentik OIDC (Kiali etc.) is Terraform under `infrastructure/terraform/cloudflare/` (Hetzner ASN allow + OIDC path skip); needs a WAF-scoped API token, not the external-dns dns-token.
- External secrets use the official 1Password Connect chart; ClusterSecretStore is `onepassword-connect` backed by vault `cloud-ops`; HelmRelease sets `installCRDs: false` because bootstrap applies ESO CRDs.
