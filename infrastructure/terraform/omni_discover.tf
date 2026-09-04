# Control-plane machine UUIDs must be supplied explicitly for HCP SaaS remote
# runs (no omnictl on stock agents). Get IDs via:
#   omnictl get machinestatuses -o yaml
# cross-reference network.hostname with hcloud_server.control_plane names, then
# set control_plane_machine_ids in the HCP workspace / tfvars.
#
# Workers are allocated from MachineClasses applied outside Terraform
# (see infrastructure/omni/workers/).

locals {
  omni_control_plane_machine_ids = distinct(compact(var.control_plane_machine_ids))
}
