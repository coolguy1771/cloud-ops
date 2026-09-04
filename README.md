# cloud-ops

Kubernetes GitOps for a Talos cluster on Hetzner Cloud, managed with Flux and bootstrapped via Helmfile.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Hetzner Cloud (Terraform)                                      │
│  Network, servers, load balancers, firewalls                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│  Talos Linux (Omni)                                             │
│  kube-proxy disabled · KubePrism :7445 · CNI none (Flux)        │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│  Cilium 1.20 (full KPR)                                         │
│  VXLAN tunnel · socketLB · cni.exclusive=false (Istio chaining) │
└────────────┬───────────────────────────────┬────────────────────┘
             │                               │
┌────────────▼────────────┐    ┌─────────────▼────────────────────┐
│  Istio Ambient Mode     │    │  Istio Gateway (ingress)         │
│  istiod · cni · ztunnel │    │  external-dns · Cloudflare proxy │
└─────────────────────────┘    └──────────────────────────────────┘
```

| Layer | Components |
|-------|------------|
| Infrastructure | Terraform (`infrastructure/terraform`) — Hetzner Cloud + Omni cluster |
| Bootstrap | Helmfile (`bootstrap/helmfile`) installs CRDs and core platform charts before Flux takes over |
| GitOps | Flux Operator + FluxInstance sync `kubernetes/flux/cluster` |
| Networking | Cilium KPR, Istio ambient mesh, Istio Gateway ingress |
| Secrets | External Secrets Operator + 1Password Connect |
| Observability | Grafana Operator, Mimir, Loki |
| CI/CD | GitHub Actions (flux-local, renovate) + ARC v2 self-hosted runners |

## Repository layout

```
.
├── bootstrap/              # Helmfile bootstrap (CRDs + platform charts); see bootstrap/README.md
├── infrastructure/
│   ├── omni/               # Talos config patches (applied by Terraform)
│   └── terraform/          # Hetzner Cloud + Omni cluster (single apply)
├── kubernetes/
│   ├── apps/               # Application namespaces (Flux Kustomizations)
│   ├── components/         # Shared Kustomize components
│   └── flux/cluster/       # Root Flux Kustomization entrypoint
└── .github/workflows/      # CI pipelines
```

## Prerequisites

- [Terraform](https://www.terraform.io/) >= 1.5
- [Helm](https://helm.sh/) >= 3.14 and [Helmfile](https://github.com/helmfile/helmfile)
- [talosctl](https://www.talos.dev/) and [omnictl](https://omni.siderolabs.com/)
- [flux](https://fluxcd.io/) CLI (optional, for local validation)
- 1Password Connect credentials and a GitHub App for automation

## Getting started

### 1. Provision infrastructure and configure Omni

Remote state and applies use HCP Terraform (`coolguy1771` / `cloud-ops`). Set
workspace variables (tokens, image ID, CP machine UUIDs, versions). Worker
MachineClasses live under `infrastructure/omni/workers/` and are applied with
`omnictl` (see that README) before the first apply that manages fsn1 workers.

```bash
cd infrastructure/terraform
# One-time: migrate local state after the cloud block is present
terraform init -migrate-state
# Or rely on GitHub Actions (plan on PR, apply on main / workflow_dispatch)
```

Local CLI still works with `TF_TOKEN_app_terraform_io` and the same workspace
vars. See `infrastructure/omni/README.md` for import steps if migrating an
existing cluster.

### 2. Bootstrap the cluster

```bash
just bootstrap cluster
```

Helmfile installs Cilium, cert-manager, external-secrets, 1Password Connect, and
Flux. Chart versions and values are read from `kubernetes/apps/` (same sources
Flux uses). See [bootstrap/README.md](bootstrap/README.md).

### 3. Verify GitOps reconciliation

```bash
flux get kustomizations -A
flux get helmreleases -A
```

Key namespaces to check:

- `kube-system/cilium` — KPR healthz on `:10256`
- `istio-system` — `istiod`, `istio-cni-node`, `ztunnel` pods running
- `actions-runner-system` — ARC controller and `cloud-ops-runner` scale set

## Istio ambient mode

Istio is installed in [ambient mode](https://istio.io/latest/docs/ambient/) via four Helm charts managed by Flux:

1. `istio-base` — CRDs and cluster roles
2. `istiod` — control plane (`profile: ambient`)
3. `istio-cni` — traffic redirection (`profile: ambient`, `HOST_PROBE_SNAT_IP` for Cilium KPR)
4. `ztunnel` — node-level L4 proxy

To enroll a namespace in the mesh:

```bash
kubectl label namespace <namespace> istio.io/dataplane-mode=ambient
```

A `CiliumClusterwideNetworkPolicy` (`allow-ambient-hostprobes`) is included so kubelet health probes work when default-deny network policies are in use.

## Cilium kube-proxy replacement

Cilium is configured for full KPR with Istio compatibility:

| Setting | Value | Purpose |
|---------|-------|---------|
| `kubeProxyReplacement` | `true` | Replace kube-proxy entirely |
| `socketLB.hostNamespaceOnly` | `true` | Avoid interfering with Istio proxies |
| `cni.exclusive` | `false` | Allow Istio CNI plugin chaining |
| `bpf.masquerade` | `false` | Use iptables masquerading (required for Istio ambient probes) |
| `k8sServiceHost` / `k8sServicePort` | `127.0.0.1:7445` | Route API traffic through KubePrism |

## GitHub Actions runners

Self-hosted runners use [Actions Runner Controller v2](https://github.com/actions/actions-runner-controller) (`gha-runner-scale-set`).

| Resource | Details |
|----------|---------|
| Scale set | `cloud-ops-runner` (0–3 runners) |
| Runner image | `ghcr.io/home-operations/actions-runner` |
| Storage | `hcloud-volumes` (25 Gi work volume) |
| Secrets | 1Password item `actions-runner` via External Secrets |

### Required secrets

| Secret | Used by |
|--------|---------|
| `BOT_APP_ID` / `BOT_APP_PRIVATE_KEY` | Renovate, flux-local, Tag workflows |
| 1Password Connect (`actions-runner` item) | Runner GitHub App credentials |

## CI/CD workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `flux-local.yaml` | PR to `main` | Validate and diff Kubernetes manifests |
| `renovate.yaml` | Hourly cron, push, manual | Dependency updates |
| `tag.yaml` | Monthly cron, manual | Create `YYYY.M.patch` release tags |
| `label-sync.yaml` | Daily cron, push | Sync GitHub labels from `.github/labels.yaml` |

## Local development

Validate manifests before pushing:

```bash
# Build a specific Flux Kustomization locally
just kube render-local-ks flux-system cluster-apps

# Run flux-local test (same as CI)
docker run --rm -v "$(pwd):/github/workspace" \
  -e GITHUB_TOKEN ghcr.io/allenporter/flux-local:v8.0.1 \
  test --all-namespaces --enable-helm \
  --path /github/workspace/kubernetes/flux/cluster --verbose
```

## Upgrading

Renovate opens PRs for Helm chart and container image updates. Platform upgrades (Talos, Kubernetes) are set in `infrastructure/terraform/terraform.tfvars` (`talos_version`, `kubernetes_version`).

When upgrading Istio, bump the `tag` in all four `OCIRepository` manifests under `kubernetes/apps/istio-system/istio/app/` and add or update the matching CRD entry in `bootstrap/helmfile/crds.yaml` if needed.

## License

See repository license file if present.
