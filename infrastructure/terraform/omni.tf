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

# The workers machine set is defined in hetzner_infra_provider.tf — it draws
# from a MachineClass (dynamic allocation) rather than being declared here.

resource "omni_machine_set_node" "control_plane" {
  for_each = toset(local.omni_control_plane_machine_ids)

  cluster     = omni_cluster.this.name
  machine_id  = each.value
  machine_set = omni_machine_set.control_plane.name
}
