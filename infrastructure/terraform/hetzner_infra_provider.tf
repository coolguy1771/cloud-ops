# Dynamic worker provisioning via the Hetzner Omni infra provider
# (github.com/coolguy1771/hetzner-infra-provider). The daemon itself is NOT
# managed by this repo — it runs elsewhere. Terraform only owns:
#   - one MachineClass Omni object per Hetzner location in var.worker_locations
#     (applied via `omnictl apply`, since the siderolabs/omni Terraform
#     provider (0.1.0-alpha.3) has no native resource for it yet)
#   - one worker machine set per location, which draws from that class instead
#     of explicit omni_machine_set_node assignments
#
# Multi-region works as N independent (MachineClass, machine_set) pairs
# rather than one pool the provider spreads across locations itself — the
# Hetzner infra provider only ever sees a single `location` per MachineClass,
# so each region needs its own class + set, each with its own worker count.
#
# One-time manual prerequisite, run once against your Omni instance
# (mints a credential, so it is intentionally not automated here):
#
#   omnictl infraprovider create ${var.hetzner_infra_provider_id}
#
# Feed the resulting OMNI_SERVICE_ACCOUNT_KEY, plus an HCLOUD_TOKEN, to
# wherever you run the daemon.

locals {
  # This is what our own Hetzner infra provider's Data struct
  # (internal/pkg/provider/data.go, UnmarshalProviderData) decodes — one
  # rendered blob per location.
  hetzner_worker_provider_data_yaml = {
    for location, count in var.worker_locations : location => yamlencode({
      server_type = var.worker_server_type
      location    = location
      networks    = [hcloud_network.this.name]
      firewalls   = [hcloud_firewall.worker.name]
      labels = {
        cluster = var.cluster_name
        role    = "worker"
        region  = location
      }
    })
  }

  hetzner_worker_machine_class_names = {
    for location in keys(var.worker_locations) : location => "${var.cluster_name}-hetzner-workers-${location}"
  }

  # `omnictl apply` decodes files as raw COSI resources: exactly two top-level
  # keys, metadata + spec (see cosi-project/runtime's
  # protobuf.YAMLResource.UnmarshalYAML) — there is no apiVersion/kind
  # wrapper, despite what some infra provider READMEs show (that shorthand
  # appears to be UI-only). MachineClassSpec
  # (client/api/omni/specs/omni.proto) has no explicit yaml struct tags, so
  # go.yaml.in/yaml matches fields by lowercased Go field name:
  # AutoProvision -> autoprovision, ProviderId -> providerid,
  # ProviderData -> providerdata. Verified against a live Omni instance with
  # `omnictl apply --dry-run --verbose` before wiring this up.
  hetzner_worker_machine_class_yaml = {
    for location in keys(var.worker_locations) : location => yamlencode({
      metadata = {
        namespace = "default"
        type      = "MachineClasses.omni.sidero.dev"
        id        = local.hetzner_worker_machine_class_names[location]
      }
      spec = {
        autoprovision = {
          providerid   = var.hetzner_infra_provider_id
          providerdata = local.hetzner_worker_provider_data_yaml[location]
        }
      }
    })
  }
}

# Write the rendered YAML with Terraform itself (not a shell heredoc) so its
# indentation can't get mangled by heredoc whitespace-trimming — a nested
# `<<-EOT ... ${...} ... EOT` previously corrupted the nested YAML structure.
resource "local_file" "hetzner_worker_machine_class" {
  for_each = var.worker_locations

  filename        = "${path.module}/.generated/hetzner-worker-machine-class-${each.key}.yaml"
  content         = local.hetzner_worker_machine_class_yaml[each.key]
  file_permission = "0600"
}

# omnictl apply is idempotent, so re-running it whenever the rendered file
# changes is safe. This is a stand-in for a native `omni_machine_class`
# resource, which the Terraform provider does not support yet.
resource "null_resource" "hetzner_worker_machine_class" {
  for_each = var.worker_locations

  triggers = {
    yaml_sha256 = local_file.hetzner_worker_machine_class[each.key].content_sha256
  }

  provisioner "local-exec" {
    command = "omnictl apply -f ${local_file.hetzner_worker_machine_class[each.key].filename}"
  }
}

# One worker machine set per location, each allocating from that location's
# MachineClass instead of explicit omni_machine_set_node assignments. Control
# plane remains static (see omni.tf) — dynamic/auto-provisioned control
# planes are not something Omni's machine_class supports (bootstrap_spec is
# control-plane-only), and fixed control-plane identity is what etcd quorum
# wants anyway.
#
# Only fsn1 uses this native resource — see the "extra worker machine sets"
# block below for why every other location is applied as raw COSI YAML
# instead.
resource "omni_machine_set" "workers" {
  for_each = { for location, count in var.worker_locations : location => count if location == "fsn1" }

  cluster = omni_cluster.this.name
  role    = "workers"
  # Deliberately not set: Omni's backend always prepends the cluster name to
  # whatever `name` is configured here server-side, and the provider (an
  # early alpha, 0.1.0-alpha.3) doesn't reconcile that — it returns the
  # server-transformed value and Terraform rejects it as "inconsistent
  # result after apply" no matter what string is configured. Leaving this
  # unset makes it purely provider-computed, which sidesteps the consistency
  # check entirely. omni_patches.tf already references the resulting name
  # dynamically (never a hardcoded string), so this needs no other changes.
  #
  # The catch discovered running this multi-region: Omni computes this
  # resource's ID from cluster+role alone, *not* from anything in Terraform's
  # for_each key, so every location resolves to the exact same Omni object
  # ("<cluster>-workers"). Only the first location to successfully create it
  # can ever use this resource — every other one fails with AlreadyExists.
  # fsn1 got there first (it's what's live today), so it's the one location
  # still managed this way; nbg1/hel1/etc. are applied below instead, with
  # an explicit unique id, same as the MachineClasses above.
  machine_class = {
    name            = local.hetzner_worker_machine_class_names[each.key]
    size            = each.value
    allocation_type = var.worker_allocation_type
  }

  update_strategy = {
    type            = "Rolling"
    max_parallelism = 2
  }

  depends_on = [null_resource.hetzner_worker_machine_class]
}

# Extra worker machine sets (every location except fsn1, see comment above).
# Applied as raw COSI YAML via `omnictl apply` — same workaround as the
# MachineClasses, and for the same underlying reason: the Terraform provider
# can't give each one a distinct, stable identity. Structure verified against
# a live Omni instance (`omnictl get machineset cloud-ops-workers -o yaml`)
# and with `omnictl apply --dry-run --verbose` before wiring this up.
locals {
  hetzner_worker_extra_locations = [for location in keys(var.worker_locations) : location if location != "fsn1"]

  hetzner_worker_machine_set_names = {
    for location in local.hetzner_worker_extra_locations : location => "${var.cluster_name}-workers-${location}"
  }

  hetzner_worker_machine_set_yaml = {
    for location in local.hetzner_worker_extra_locations : location => yamlencode({
      metadata = {
        namespace = "default"
        type      = "MachineSets.omni.sidero.dev"
        id        = local.hetzner_worker_machine_set_names[location]
        labels = {
          "omni.sidero.dev/cluster"     = omni_cluster.this.name
          "omni.sidero.dev/role-worker" = ""
        }
      }
      spec = {
        updatestrategy = 1 # Rolling — matches update_strategy.type = "Rolling" above
        updatestrategyconfig = {
          rolling = {
            maxparallelism = 2
          }
        }
        machineallocation = {
          name         = local.hetzner_worker_machine_class_names[location]
          machinecount = var.worker_locations[location]
          # 0 = Static, 1 = Unlimited — matches the native resource's
          # allocation_type ordinals for the only two allocation_type values
          # this provider supports.
          allocationtype = var.worker_allocation_type == "Unlimited" ? 1 : 0
        }
      }
    })
  }
}

resource "local_file" "hetzner_worker_machine_set" {
  for_each = toset(local.hetzner_worker_extra_locations)

  filename        = "${path.module}/.generated/hetzner-worker-machine-set-${each.key}.yaml"
  content         = local.hetzner_worker_machine_set_yaml[each.key]
  file_permission = "0600"
}

resource "null_resource" "hetzner_worker_machine_set" {
  for_each = toset(local.hetzner_worker_extra_locations)

  triggers = {
    yaml_sha256 = local_file.hetzner_worker_machine_set[each.key].content_sha256
  }

  provisioner "local-exec" {
    command = "omnictl apply -f ${local_file.hetzner_worker_machine_set[each.key].filename}"
  }

  depends_on = [null_resource.hetzner_worker_machine_class]
}
