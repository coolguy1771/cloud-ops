# Cluster lifecycle is managed by Terraform using the [official Omni provider](https://registry.terraform.io/providers/siderolabs/omni/latest/docs).

Machines are assigned explicitly via `omni_machine_set_node` — this cluster does not use Omni machine classes. Machine UUIDs are discovered at plan time from `omnictl` label selectors.

| Path | Purpose |
|------|---------|
| `patches/all-nodes.yaml` | Cluster-wide Talos patches (CNI none, kube-proxy off, KubePrism) |
| `patches/controlplane.yaml` | Control plane Talos API access for CCM and runners |
| `patches/install-disk.yaml` | Install disk (`/dev/sda`) for all nodes |
| `../terraform/omni.tf` | Cluster, machine sets, and machine assignments |
| `../terraform/omni_patches.tf` | Applies patch files via `omni_config_patch` resources |
| `../terraform/scripts/import-omni.sh` | One-shot import of existing Omni state |

## Do not use `omnictl cluster template sync`

Terraform is the single source of truth for this cluster. Avoid editing the same resources in the Omni UI or via cluster templates — changes will be overwritten on the next `terraform apply`.

## Import existing cluster (start here)

If the cluster already exists in Omni, import before the first `terraform apply`.

### 1. Authenticate

Terraform uses a **service account key**, not your `omnictl` user session. Discovery via `omnictl` can work while Terraform import fails with `invalid signature` if only user auth is configured.

```bash
# Create a service account (while logged into omnictl)
omnictl serviceaccount create --use-user-role=false --role Admin terraform

# Export the base64 key from the output — not your omnictl token
export OMNI_SERVICE_ACCOUNT_KEY="<base64-key>"

# Optional if not in terraform.tfvars (import script reads omnictl context URL)
export OMNI_ENDPOINT="https://your-instance.omni.siderolabs.io"
```

Set `omni_endpoint` in `infrastructure/terraform/terraform.tfvars` to avoid prompts during `terraform plan`.

### 2. Discover resource IDs (optional)

Confirm names match your Omni instance:

```bash
omnictl get clusters -o yaml | grep "id:"
omnictl get machinesets -l omni.sidero.dev/cluster=cloud-ops -o yaml | grep "id:"
omnictl get configpatches -l omni.sidero.dev/cluster=cloud-ops -o yaml | grep "id:"
```

### 3. Run the import script

The script autodiscovers resource IDs from Omni using label selectors (`omni.sidero.dev/cluster`, role labels, and config patch ID patterns). Cluster name is read from `CLUSTER_NAME`, `terraform.tfvars`, or defaults to `cloud-ops`.

```bash
cd infrastructure/terraform
terraform init
chmod +x scripts/import-omni.sh
./scripts/import-omni.sh
terraform plan
```

The script is idempotent — it skips resources already in state.

Preview what will be discovered:

```bash
CLUSTER=cloud-ops
omnictl get machinesets -l omni.sidero.dev/cluster=$CLUSTER -o yaml | grep "    id:"
omnictl get clustermachines -l omni.sidero.dev/cluster=$CLUSTER -o yaml | grep -E "    id:|role-"
omnictl get configpatches -l omni.sidero.dev/cluster=$CLUSTER -o yaml | grep "    id:"
```

### 4. Manual import (if you prefer)

Import IDs follow the [provider rules](https://registry.terraform.io/providers/siderolabs/omni/latest/docs):

| Resource | Import ID |
|----------|-----------|
| `omni_cluster` | Cluster name |
| `omni_machine_set` | Machine set ID from `omnictl get machinesets` |
| `omni_machine_set_node` | Machine UUID only |
| `omni_config_patch` | Full patch ID from `omnictl get configpatches` |

### 5. Review the plan

After import, `terraform plan` should show no changes, or only patch `data` diffs if you updated the YAML files. Do not apply if the plan wants to **replace** machine sets or the cluster.

Hetzner resources (`hcloud_*`) are separate — import those only if Terraform state is empty but servers already exist in Hetzner.

## Upgrade Talos (via Terraform)

Cluster versions are set in `terraform.tfvars`:

```hcl
kubernetes_version = "1.36.1"      # Talos 1.14 supports 1.37, 1.36, 1.35, ...
talos_version      = "1.14.0-rc.1" # bump to 1.14.0 after GA
```

Talos 1.14 patches in `patches/` use multidoc config kinds (`KubeProxyConfig`, `KubePrismConfig`, etc.). They require the cluster `talos_version` to be 1.14 — applying them on 1.13 fails with `not registered`.

```bash
cd infrastructure/terraform
terraform plan   # expect omni_cluster + omni_config_patch changes
terraform apply  # Omni rolls nodes to the new Talos version
```

After upgrading Talos, register a matching Hetzner install image in Omni and update `talos_image_id` if you replace nodes. Existing nodes upgrade in place via Omni.

## Apply (new clusters only)

```bash
cd infrastructure/terraform
terraform init
terraform plan
terraform apply
```
