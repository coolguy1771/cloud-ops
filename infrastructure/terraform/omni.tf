# Omni cluster lifecycle — managed via the official Sidero Omni Terraform provider.
# https://docs.siderolabs.com/omni/cluster-management/terraform-and-omni
#
# Authenticate with OMNI_SERVICE_ACCOUNT_KEY (base64 service account key from
# `omnictl serviceaccount create`) and set omni_endpoint in terraform.tfvars.

resource "omni_cluster" "this" {
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
}

resource "omni_machine_set" "control_plane" {
  cluster = omni_cluster.this.name
  role    = "controlplane"
}

resource "omni_machine_set" "workers" {
  cluster = omni_cluster.this.name
  role    = "workers"

  update_strategy = {
    type            = "Rolling"
    max_parallelism = 2
  }
}

resource "omni_machine_set_node" "control_plane" {
  for_each = toset(local.omni_control_plane_machine_ids)

  cluster     = omni_cluster.this.name
  machine_id  = each.value
  machine_set = omni_machine_set.control_plane.name
}

resource "omni_machine_set_node" "worker" {
  for_each = toset(local.omni_worker_machine_ids)

  cluster     = omni_cluster.this.name
  machine_id  = each.value
  machine_set = omni_machine_set.workers.name
}
