# Dynamic worker provisioning via the Hetzner Omni infra provider
# (github.com/coolguy1771/hetzner-infra-provider). The daemon itself is NOT
# managed by this repo — it runs elsewhere.
#
# Single Hetzner region (fsn1): the cluster was consolidated from fsn1/nbg1/hel1
# to one region because synchronous DB replication and etcd round-trips across
# Hetzner regions hurt performance.
#
# Provider v0.1.0-beta.0 introduced native resources for the pieces this file
# used to wire together with checked-in YAML + a manual `omnictl` step:
#
#   - omni_infra_provider.hetzner  registers the infra provider + service account
#     (replaces `omnictl infraprovider create hetzner`).
#   - omni_machine_class           manages the worker MachineClass from Terraform
#     (replaces infrastructure/omni/workers/machine-class-fsn1.yaml).
#
# Import the existing objects before the first apply that would otherwise try
# to create them (see scripts/import-omni.sh):
#   terraform import omni_infra_provider.hetzner hetzner
#   terraform import omni_machine_class.hetzner_workers_fsn1 cloud-ops-hetzner-workers-fsn1
#
# Key-recovery caveat: an imported omni_infra_provider has key = null because
# Omni never returns the private half. The running daemon keeps the key it was
# originally given; Terraform cannot recover it. To rotate, destroy + recreate
# the resource (new key in state) and re-feed the daemon.

# Registers the Hetzner infrastructure provider in Omni and the
# `infra-provider:hetzner` service account it authenticates as. The generated
# `key` is what OMNI_SERVICE_ACCOUNT_KEY expects for the infra-provider daemon.
resource "omni_infra_provider" "hetzner" {
  name = var.hetzner_infra_provider_name
  ttl  = var.hetzner_infra_provider_ttl
}

# The single worker MachineClass: auto-provisioned fsn1 workers via the Hetzner
# infra provider. provider_data is the Hetzner-specific machine spec, passed
# verbatim to the infra provider. Firewall/network names reference the hcloud
# resources so a cluster_name change stays consistent without editing YAML.
resource "omni_machine_class" "hetzner_workers_fsn1" {
  name = "${var.cluster_name}-hetzner-workers-fsn1"

  auto_provision = {
    provider_id = omni_infra_provider.hetzner.name

    provider_data = yamlencode({
      firewalls = [hcloud_firewall.worker.name]
      labels = {
        cluster = var.cluster_name
        region  = "fsn1"
        role    = "worker"
      }
      location    = "fsn1"
      networks    = [hcloud_network.this.name]
      server_type = var.worker_server_type
    })
  }
}

# fsn1 worker machine set. Omni's native machine_set ID is cluster+role only, so
# only one location can use this native resource. The cluster is single-region
# (fsn1); see infrastructure/omni/workers/README.md for the consolidation history.
# Referencing omni_machine_class.hetzner_workers_fsn1.name creates an implicit
# dependency, so the MachineClass always exists before the machine set.
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
    name            = omni_machine_class.hetzner_workers_fsn1.name
    size            = each.value
    allocation_type = var.worker_allocation_type
  }

  update_strategy = {
    type            = "Rolling"
    max_parallelism = 2
  }
}
