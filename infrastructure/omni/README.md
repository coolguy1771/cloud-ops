# Cluster lifecycle is managed by Terraform using the [official Omni provider](https://registry.terraform.io/providers/siderolabs/omni/latest/docs)
# via **HCP Terraform VCS** (org `coolguy1771`, workspace `cloud-ops`, working
# directory `infrastructure/terraform`). Stock SaaS agents run plan/apply on
# Git changes; they do not have `omnictl`.

| Path | Purpose |
|------|---------|
| `patches/all-nodes.yaml` | Cluster-wide Talos patches (CNI none, kube-proxy off, KubePrism) |
| `patches/controlplane.yaml` | Control plane Talos API access for CCM and runners |
| `patches/install-disk.yaml` | Install disk (`/dev/sda`) for all nodes |
| `workers/` | MachineClasses + non-fsn1 machine sets (`omnictl apply` only) |
| `../terraform/omni.tf` | Cluster, CP machine set, node assignments |
| `../terraform/omni_patches.tf` | Applies patch files via `omni_config_patch` resources |
| `../terraform/scripts/import-omni.sh` | One-shot import of existing Omni state (local CLI) |

## Do not use `omnictl cluster template sync`

Terraform is the source of truth for resources it owns. Avoid editing those in
the Omni UI or via cluster templates — changes will be overwritten on the next
apply. Worker MachineClasses / non-fsn1 sets are owned by the YAML in `workers/`
instead.

## HCP VCS workflow

- PRs that touch `infrastructure/terraform/**` (excluding `cloudflare/`) or
  `infrastructure/omni/patches/**` get a speculative plan in HCP.
- Merges to `main` auto-apply.
- Workspace variables hold tokens and tfvars (not git).
- GitHub Actions only runs fmt / validate / TFLint / Trivy.

## Workers (`omnictl`)

See [workers/README.md](workers/README.md). Apply MachineClass YAML before the
first HCP run that manages `omni_machine_set.workers` for fsn1.

## Authenticate (local import / CLI)

Terraform uses a **service account key**, not your `omnictl` user session.

```bash
omnictl serviceaccount create --use-user-role=false --role Admin terraform
export OMNI_SERVICE_ACCOUNT_KEY="<base64-key>"
export OMNI_ENDPOINT="https://your-instance.omni.siderolabs.io"
```

Remote runs read the same values from **workspace variables**.

## Import existing cluster

If the cluster already exists in Omni, import before the first apply (local CLI
with `OMNI_SERVICE_ACCOUNT_KEY`, after `terraform init` against the HCP workspace):

```bash
cd infrastructure/terraform
terraform init
./scripts/import-omni.sh
```

See script header for details. Do not apply if the plan wants to **replace**
machine sets or the cluster.

## Control plane machine IDs

Set `control_plane_machine_ids` in the HCP workspace (no live discovery):

```bash
omnictl get machinestatuses -o yaml
# Match network.hostname to cloud-ops-cp-1/2/3
```

## Upgrade Talos (via Terraform / HCP)

Bump `kubernetes_version` / `talos_version` workspace variables, open a PR for
the speculative plan, then merge to auto-apply.
