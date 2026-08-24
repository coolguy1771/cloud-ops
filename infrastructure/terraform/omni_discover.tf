# Discover control plane machines already assigned to the cluster, via
# omnictl labels. This only ever finds machines that are already
# ClusterMachines (i.e. already assigned to this cluster's control-plane
# machine set) — it can't discover a freshly booted, never-yet-assigned
# machine, since Terraform has no way to know a server's Talos machine UUID
# until minutes after `apply`, once it boots and registers with Omni over
# siderolink. That's what var.control_plane_machine_ids is for: bootstrapping
# brand-new control-plane servers into the cluster for the first time (get
# UUIDs via `omnictl get machinestatuses -o yaml`, cross-referencing the
# `network.hostname` field against your hcloud_server.control_plane names —
# do not guess/assume which unassigned machine is which). Once assigned, they
# show up via this discovery script too, so the union below stays stable
# after the fact — no need to remove them from the variable again.
#
# Workers are allocated dynamically from a MachineClass instead (see
# hetzner_infra_provider.tf), so they need no discovery/bootstrap step here.
data "external" "omni_machines" {
  program = ["bash", "${path.module}/scripts/omni-discover.sh"]

  query = {
    cluster = var.cluster_name
  }
}

locals {
  omni_control_plane_machine_ids = distinct(concat(
    compact(split(",", data.external.omni_machines.result.control_plane_ids)),
    var.control_plane_machine_ids,
  ))
}
