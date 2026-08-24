## Learned User Preferences

- Port platform patterns from `coolguy1771/home-ops` or `onedr0p/home-ops`, adapting cloud-ops-specific names (repo URL, vault, scale set) instead of copying upstream identifiers verbatim.
- Manage Omni cluster lifecycle with Terraform (`siderolabs/omni` provider); do not use `omnictl cluster template sync` or manual Omni UI edits for resources Terraform owns.
- Merge non-major Renovate PRs in `coolguy1771/cloud-ops` and `coolguy1771/home-ops` when CI is clean; skip `type/major` PRs and PRs with failing checks.
- When porting external-secrets from home-ops, keep the `cloud-ops` 1Password vault name and `onepassword-connect` ClusterSecretStore naming.
- Prefer Flux walking `kubernetes/apps/` directories over maintaining a root `kubernetes/apps/kustomization.yaml`.

## Learned Workspace Facts

- GitOps repo for Talos cluster `cloud-ops` on Hetzner Cloud: Flux reconciles `kubernetes/`, Helmfile bootstraps via `bootstrap/helmfile/`.
- GitHub repos: `coolguy1771/cloud-ops` (this repo), `coolguy1771/home-ops` (reference fork of onedr0p patterns).
- kube-proxy is disabled in Omni patches; Cilium full KPR uses KubePrism on port 7445; patches use Talos 1.13-compatible inline machine config (not 1.14 multidoc kinds).
- Cilium is tuned for Istio ambient: `cni.exclusive: false`, `socketLB.hostNamespaceOnly: true`, `bpf.masquerade: false`, `envoy.enabled: false`.
- Istio ambient is Flux-managed under `kubernetes/apps/istio-system/` (base, istiod, cni, ztunnel); Helm charts use `oci://gcr.io/istio-release/charts/{base,istiod,cni,ztunnel}` (not image repos under `oci://gcr.io/istio-release/{...}`); ingress remains Envoy Gateway in `kubernetes/apps/network/envoy-gateway/`.
- CI/CD workflows: `image-pull`, `tag`, `flux-local`, `renovate`, `label-sync`; `image-pull` and `tag` were ported from home-ops.
- Self-hosted runners use ARC v2 (`gha-runner-scale-set-controller` / `gha-runner-scale-set`) with scale set `cloud-ops-runner` (0-3) in `actions-runner-system`, targeting `github.com/coolguy1771/cloud-ops`.
- Omni Terraform lives in `infrastructure/terraform/` with provider `siderolabs/omni` v0.1.0-alpha.3; Talos patches are `omni_config_patch` resources in `omni_patches.tf`; auth requires `OMNI_SERVICE_ACCOUNT_KEY`.
- Import an existing Omni cluster with `infrastructure/terraform/scripts/import-omni.sh` (omnictl autodiscovery) before the first `terraform apply`; machine sets are `cloud-ops-control-planes` and `cloud-ops-workers`.
- Control planes are static `hcloud_server` with explicit Omni node assignment; workers use Hetzner Omni infra provider MachineClasses (`hetzner_infra_provider.tf` / `coolguy1771/hetzner-infra-provider`).
- External secrets use the official 1Password Connect chart; ClusterSecretStore is `onepassword-connect` backed by vault `cloud-ops`; HelmRelease sets `installCRDs: false` because bootstrap applies ESO CRDs.
- Runner pods set `securityContext.allowPrivilegeEscalation: false` on the runner container in `kubernetes/apps/actions-runner-system/actions-runner-controller/runners/cloud-ops/helmrelease.yaml`.
