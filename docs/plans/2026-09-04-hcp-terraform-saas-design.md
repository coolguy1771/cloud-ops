# HCP Terraform SaaS remote apply (cloud-ops)

## Goal

Run `infrastructure/terraform` plan/apply on stock HCP Terraform SaaS agents with remote state in org `coolguy1771`, workspace `cloud-ops`. CI triggers runs from GitHub Actions; provider secrets live as HCP workspace env vars.

## Constraints

- Stock SaaS agents have no `omnictl`.
- Root module today shells out for CP discovery (`data.external`) and worker MachineClass / non-fsn1 machine sets (`local-exec`).
- Cloudflare stack under `infrastructure/terraform/cloudflare/` stays out of this workspace/workflow.

## Decisions

| Topic | Choice |
|-------|--------|
| State | HCP Terraform |
| Org / workspace | `coolguy1771` / `cloud-ops` |
| Execution | Stock SaaS remote agents |
| Secrets | HCP workspace environment variables only |
| Apply triggers | Merge to `main` (path-filtered) + `workflow_dispatch`; PR = plan only |
| Apply gate | GitHub Environment (e.g. `terraform`) with required reviewers |
| omnictl MachineClasses / extra worker sets | Removed from Terraform; `omnictl apply` only |
| CP machine IDs | Workspace/tf var `control_plane_machine_ids` only (no live discovery) |

## Target ownership

**HCP remote (Terraform):**

- All `hcloud_*` resources
- `omni_cluster`, CP `omni_machine_set`, `omni_machine_set_node`, `omni_config_patch`
- Native `omni_machine_set.workers` for `fsn1` only (references MachineClass by name; class must already exist)

**Outside Terraform (`omnictl apply`, checked-in YAML):**

- Worker MachineClasses per location
- Worker machine sets for locations other than `fsn1` (provider ID collision workaround)

Suggested path: `infrastructure/omni/workers/` plus short README steps.

## Module changes

1. Add `cloud` block: organization `coolguy1771`, workspace `cloud-ops`.
2. Delete `data.external.omni_machines` / `scripts/omni-discover.sh` usage; build CP ID set from `var.control_plane_machine_ids` only.
3. Remove `local_file` / `null_resource` MachineClass and extra machine-set provisioners from `hetzner_infra_provider.tf`; drop `depends_on` on those null resources from native worker set.
4. Export static YAML (generated from current locals or hand-maintained) under `infrastructure/omni/workers/`.
5. Document: update worker YAML + `omnictl apply` when `worker_locations` / types change; ensure MachineClass exists before HCP apply that touches `omni_machine_set.workers`.
6. Keep CP sizing as `cx33` via `control_plane_server_type` / `control_plane_server_types`.

## HCP workspace setup

- Execution mode: Remote (SaaS).
- Env vars (sensitive as needed): `HCLOUD_TOKEN` or `TF_VAR_hcloud_token`, `OMNI_SERVICE_ACCOUNT_KEY` or `TF_VAR_omni_service_account_key`, `OMNI_ENDPOINT` / `TF_VAR_omni_endpoint`, plus non-secret tfvars currently in `terraform.tfvars` that should not stay only on laptops (image ID, locations, versions, machine IDs). Prefer workspace variables over committing secrets.
- Migrate existing local state once: `terraform init -migrate-state` after `cloud` block is in place.
- Optional HCP run approvals in addition to GitHub Environment.

## GitHub Actions

- Runner: can use `ubuntu-latest` (no omnictl on the job); only needs Terraform CLI + `TF_TOKEN_app_terraform_io` (or GitHub OIDC → HCP if configured later).
- Path filter: `infrastructure/terraform/**` (exclude `cloudflare/` if easy).
- PR: create plan run, wait, post summary; never apply.
- `main` + `workflow_dispatch`: plan then apply via HCP API / `hashicorp/tfc-workflows-github`, gated by Environment `terraform`.
- Concurrency group per workspace to avoid overlapping applies.

## Out of scope

- Cloudflare Terraform root
- Custom HCP Agents / ARC-based local execution
- Replacing Omni alpha provider limitations for multi-region worker machine sets

## Success criteria

- `terraform plan` in HCP shows no omnictl / local-exec errors.
- PR opens a speculative plan; merge/`workflow_dispatch` can apply with approval.
- Worker class/size changes are an explicit `omnictl apply` of checked-in YAML, not a Terraform apply.
- Local `terraform.tfstate` retired after successful migrate; backups retained outside git.
