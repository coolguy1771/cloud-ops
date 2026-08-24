locals {
  omni_patch_dir = "${path.module}/../omni/patches"
}

# Cluster-wide Talos patches (CNI none, kube-proxy disabled, KubePrism, host DNS).
resource "omni_config_patch" "all_nodes" {
  name    = "patches/all-nodes.yaml"
  weight  = 200
  cluster = omni_cluster.this.name
  data    = file("${local.omni_patch_dir}/all-nodes.yaml")
}

# Control plane only — Talos API access for CCM and runners.
resource "omni_config_patch" "control_plane" {
  name    = "patches/controlplane.yaml"
  weight  = 400
  cluster = omni_cluster.this.name

  selector = {
    machine_set = omni_machine_set.control_plane.name
  }

  data = file("${local.omni_patch_dir}/controlplane.yaml")
}

# Install disk — one patch per machine set. Using a machine_set selector
# (rather than per-cluster_machine) means dynamically auto-provisioned
# workers get this patch automatically too, without Terraform needing to know
# their machine IDs in advance.
resource "omni_config_patch" "install_disk" {
  for_each = merge(
    { control_plane = omni_machine_set.control_plane.name },
    { for location, ms in omni_machine_set.workers : "workers_${location}" => ms.name },
    # fsn1 above is native-provider-managed; every other worker location is
    # applied as raw COSI YAML (see hetzner_infra_provider.tf) where the id
    # we chose *is* the machine set's name.
    { for location, name in local.hetzner_worker_machine_set_names : "workers_${location}" => name }
  )

  name    = "install-disk"
  weight  = 0
  cluster = omni_cluster.this.name

  selector = {
    machine_set = each.value
  }

  data = file("${local.omni_patch_dir}/install-disk.yaml")

  depends_on = [null_resource.hetzner_worker_machine_set]
}
