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

# Install disk — one patch per machine (matches existing Omni template layout).
resource "omni_config_patch" "install_disk" {
  for_each = toset(local.omni_machine_ids)

  name    = "install-disk"
  weight  = 0
  cluster = omni_cluster.this.name

  selector = {
    cluster_machine = each.value
  }

  data = file("${local.omni_patch_dir}/install-disk.yaml")
}
