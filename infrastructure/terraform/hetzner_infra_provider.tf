# Dynamic worker provisioning via the Hetzner Omni infra provider
# (github.com/coolguy1771/hetzner-infra-provider). The daemon itself is NOT
# managed by this repo — it runs elsewhere.
#
# MachineClasses and non-fsn1 worker machine sets are applied with omnictl from
# checked-in YAML under infrastructure/omni/workers/ (stock HCP SaaS agents
# have no omnictl). Terraform only owns the native fsn1 omni_machine_set.workers
# resource, which references a MachineClass by name — apply the YAML first.
#
# One-time manual prerequisite:
#   omnictl infraprovider create ${var.hetzner_infra_provider_id}
# Feed the resulting key + HCLOUD_TOKEN to the infra-provider daemon.

locals {
  hetzner_worker_machine_class_names = {
    for location in keys(var.worker_locations) : location => "${var.cluster_name}-hetzner-workers-${location}"
  }

  # Extra locations (not fsn1): machine set IDs used by omni_config_patch
  # install_disk selectors. These sets are created via omnictl, not Terraform
  # — Omni's native machine_set ID is cluster+role only, so only fsn1 can use
  # omni_machine_set.workers; see infrastructure/omni/workers/README.md.
  hetzner_worker_extra_locations = [
    for location in keys(var.worker_locations) : location if location != "fsn1"
  ]

  hetzner_worker_machine_set_names = {
    for location in local.hetzner_worker_extra_locations :
    location => "${var.cluster_name}-workers-${location}"
  }
}

# Only fsn1 uses this native resource — other locations are omnictl-applied YAML
# (provider cannot give each location a distinct Omni machine set identity).
resource "omni_machine_set" "workers" {
  for_each = {
    for location, count in var.worker_locations : location => count if location == "fsn1"
  }

  cluster = omni_cluster.this.name
  role    = "workers"
  # Deliberately not set: Omni prepends the cluster name server-side and the
  # alpha provider rejects a configured name as inconsistent after apply.
  # Leaving name unset makes it provider-computed.

  machine_class = {
    name            = local.hetzner_worker_machine_class_names[each.key]
    size            = each.value
    allocation_type = var.worker_allocation_type
  }

  update_strategy = {
    type            = "Rolling"
    max_parallelism = 2
  }
}
