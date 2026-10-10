# Omni worker MachineClass — Terraform-managed

As of Omni Terraform provider v0.1.0-beta.0, the worker MachineClass and the
Hetzner infra provider are owned by Terraform resources, so there is no more
`omnictl apply` YAML prerequisite for this directory. The files that used to
live here were removed when the resources were migrated into Terraform:

| Omni object | Terraform resource |
|-------------|--------------------|
| `InfraProviders.omni.sidero.dev` (hetzner) | `omni_infra_provider.hetzner` |
| `MachineClasses.omni.sidero.dev` (fsn1) | `omni_machine_class.hetzner_workers_fsn1` |
| `MachineSets.omni.sidero.dev` (fsn1 workers) | `omni_machine_set.workers["fsn1"]` |

All three live in `infrastructure/terraform/hetzner_infra_provider.tf`. HCP SaaS
agents can now create/update them directly — no `omnictl` on the agent.

## What changed and why

The cluster previously spanned `fsn1` / `nbg1` / `hel1`; it was consolidated to
a single region (`fsn1`) because synchronous DB replication and etcd round-trips
across Hetzner regions hurt performance. The `nbg1` / `hel1` MachineClasses and
machine sets were deleted (see git history) — re-adding them would reintroduce
the multi-region latency problem.

The fsn1 MachineClass used to be checked-in YAML applied via `omnictl` because
the alpha Terraform provider had no `omni_machine_class` resource. The beta
provider added it, so the YAML was deleted and the resource now owns the class.

## First apply against existing Omni objects (import)

The infra provider and MachineClass already exist in Omni from the manual
`omnictl` setup. Import them before the first HCP apply that would otherwise try
to create them:

```bash
terraform import omni_infra_provider.hetzner hetzner
terraform import omni_machine_class.hetzner_workers_fsn1 cloud-ops-hetzner-workers-fsn1
```

Then feed the `hetzner_infra_provider_key` output to the
`coolguy1771/hetzner-infra-provider` daemon (or keep its existing key — see the
key-recovery caveat in `hetzner_infra_provider.tf`).

## Decommissioning the old multi-region sets (one-time, already done)

When consolidating, the `nbg1` / `hel1` MachineClasses and MachineSets must be
deleted from Omni so Terraform stops tracking them:

```bash
omnictl delete machinesets cloud-ops-workers-nbg1 cloud-ops-workers-hel1
omnictl delete machineclasses cloud-ops-hetzner-workers-nbg1 cloud-ops-hetzner-workers-hel1
```
