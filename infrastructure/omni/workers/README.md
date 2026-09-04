# Omni worker MachineClasses and extra machine sets

Stock HCP Terraform SaaS agents cannot run `omnictl`. Worker MachineClasses and
non-`fsn1` machine sets are applied from this directory instead of Terraform
`local-exec` provisioners.

Terraform still manages the native `omni_machine_set.workers` for **fsn1 only**
(see `infrastructure/terraform/hetzner_infra_provider.tf`). That resource
references `cloud-ops-hetzner-workers-fsn1` by name — apply the MachineClass
YAML before the first HCP apply that creates or updates it.

## Files

| File | Omni object |
|------|-------------|
| `machine-class-<location>.yaml` | `MachineClasses.omni.sidero.dev` |
| `machine-set-<location>.yaml` | `MachineSets.omni.sidero.dev` (locations other than fsn1) |

`fsn1` has a MachineClass file but no machine-set YAML — the set is the Terraform
`omni_machine_set.workers["fsn1"]` resource (`cloud-ops-workers`).

## Apply

```bash
# After editing YAML (server type, counts, locations):
omnictl apply -f infrastructure/omni/workers/machine-class-fsn1.yaml
omnictl apply -f infrastructure/omni/workers/machine-class-nbg1.yaml
omnictl apply -f infrastructure/omni/workers/machine-class-hel1.yaml
omnictl apply -f infrastructure/omni/workers/machine-set-nbg1.yaml
omnictl apply -f infrastructure/omni/workers/machine-set-hel1.yaml
```

Keep `worker_locations` / `worker_server_type` in the HCP workspace variables in
sync with these files when you change sizes or types. Updating fsn1 count is a
Terraform apply; updating nbg1/hel1 counts is an `omnictl apply` of the
machine-set YAML (and a Terraform apply only if install-disk patch selectors change).

## Prerequisites

```bash
omnictl infraprovider create hetzner
# Run coolguy1771/hetzner-infra-provider with the minted key + HCLOUD_TOKEN
```
