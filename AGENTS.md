## Learned User Preferences

- Port platform patterns from `coolguy1771/home-ops` or `onedr0p/home-ops`, adapting cloud-ops-specific names (repo URL, vault, scale set) instead of copying upstream identifiers verbatim.
- Manage Omni cluster lifecycle with Terraform (`siderolabs/omni` provider); do not use `omnictl cluster template sync` or manual Omni UI edits for resources Terraform owns.
- Merge non-major Renovate PRs in `coolguy1771/cloud-ops` and `coolguy1771/home-ops` when CI is clean; skip `type/major` PRs and PRs with failing checks.
- When porting external-secrets from home-ops, keep the `cloud-ops` 1Password vault name and `onepassword-connect` ClusterSecretStore naming.

## Learned Workspace Facts

- GitOps repo for Talos cluster `cloud-ops` on Hetzner Cloud: Flux reconciles `kubernetes/`, Helmfile bootstraps via `bootstrap/helmfile.d/`.
- GitHub repos: `coolguy1771/cloud-ops` (this repo), `coolguy1771/home-ops` (reference fork of onedr0p patterns).
- Cluster runs Talos `1.14.0-rc.1` (target `1.14.0` at GA) on Kubernetes `1.36.1`; patches use Talos 1.14 multidoc kinds in `infrastructure/omni/patches/`.
- Cilium is tuned for Istio ambient: `cni.exclusive: false`, `socketLB.hostNamespaceOnly: true`, `bpf.masquerade: false`, `envoy.enabled: false`.
- Istio ambient mode lives in `kubernetes/apps/istio-system/` (base, istiod, cni, ztunnel); ingress remains Envoy Gateway in `kubernetes/apps/network/envoy-gateway/`.
- CI/CD workflows: `image-pull`, `tag`, `flux-local`, `renovate`, `label-sync`; `image-pull` and `tag` were ported from home-ops.
- Self-hosted runners use ARC v2 (`gha-runner-scale-set-controller` / `gha-runner-scale-set`) with scale set `cloud-ops-runner` (0-3) in `actions-runner-system`, targeting `github.com/coolguy1771/cloud-ops`.
- Omni Terraform lives in `infrastructure/terraform/` with provider `siderolabs/omni` v0.1.0-alpha.3; Talos patches are `omni_config_patch` resources in `omni_patches.tf`.
- Import an existing Omni cluster with `infrastructure/terraform/scripts/import-omni.sh` before the first `terraform apply`; machine sets are `cloud-ops-control-planes` and `cloud-ops-workers`.
- External secrets use the official 1Password Connect chart; ClusterSecretStore is `onepassword-connect` backed by vault `cloud-ops`.
- Runner pods set `securityContext.allowPrivilegeEscalation: false` on the runner container in `kubernetes/apps/actions-runner-system/actions-runner-controller/runners/cloud-ops/helmrelease.yaml`.
