# Discover machines assigned to the cluster via omnictl labels.
# This cluster uses explicit machine assignment (omni_machine_set_node), not machine classes.
data "external" "omni_machines" {
  program = ["bash", "${path.module}/scripts/omni-discover.sh"]

  query = {
    cluster = var.cluster_name
  }
}

locals {
  omni_control_plane_machine_ids = compact(split(",", data.external.omni_machines.result.control_plane_ids))
  omni_worker_machine_ids        = compact(split(",", data.external.omni_machines.result.worker_ids))
  omni_machine_ids               = concat(local.omni_control_plane_machine_ids, local.omni_worker_machine_ids)
}
