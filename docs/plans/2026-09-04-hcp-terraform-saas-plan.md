# HCP Terraform SaaS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable HCP Terraform SaaS remote plan/apply for `infrastructure/terraform` (org `coolguy1771`, workspace `cloud-ops`) by removing omnictl shell-outs and adding a GHA workflow.

**Architecture:** Stock HCP SaaS agents run native Hetzner + Omni provider resources. Worker MachineClasses and non-fsn1 machine sets move to checked-in YAML applied via `omnictl`. GHA triggers remote runs with `TF_TOKEN_app_terraform_io`; secrets live in the HCP workspace.

**Tech Stack:** Terraform >= 1.6, HCP Terraform cloud block, GitHub Actions, omnictl (manual path only)

**Design:** `docs/plans/2026-09-04-hcp-terraform-saas-design.md`

---

### Task 1: Cloud block + CP discovery removal

**Files:**
- Modify: `infrastructure/terraform/versions.tf`
- Modify: `infrastructure/terraform/omni_discover.tf`
- Delete or stop using: `infrastructure/terraform/scripts/omni-discover.sh` (keep script only if import still needs patterns; prefer delete if unused)
- Modify: `infrastructure/terraform/variables.tf` (ensure CP server types from prior fix if missing on branch)
- Modify: `infrastructure/terraform/servers.tf` (cx33 + alias_ips if missing)
- Modify: `infrastructure/terraform/terraform.tfvars.example`

- [ ] Add `cloud { organization = "coolguy1771" workspaces { name = "cloud-ops" } }`
- [ ] Replace `data.external` locals with `var.control_plane_machine_ids` only
- [ ] Carry forward `control_plane_server_types` + `alias_ips = []` + default `cx33`
- [ ] `terraform fmt` / validate locally if credentials available

### Task 2: Extract worker YAML; strip omnictl provisioners

**Files:**
- Modify: `infrastructure/terraform/hetzner_infra_provider.tf`
- Modify: `infrastructure/terraform/omni_patches.tf` (remove null_resource depends_on; keep install_disk selectors for extra locations via locals that don't need null_resource)
- Create: `infrastructure/omni/workers/*.yaml` (MachineClasses + non-fsn1 machine sets)
- Create/Update: `infrastructure/omni/workers/README.md`
- Update: `infrastructure/omni/README.md`

- [ ] Render current MachineClass + extra machine-set YAML into `infrastructure/omni/workers/`
- [ ] Remove `local_file` / `null_resource` resources
- [ ] Keep `omni_machine_set.workers` for fsn1; remove depends_on on null_resource
- [ ] Keep `local.hetzner_worker_machine_set_names` (or equivalent) for install_disk patches without provisioners
- [ ] Document `omnictl apply -f` workflow

### Task 3: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/terraform.yaml`

- [ ] PR: path filter `infrastructure/terraform/**` excluding `cloudflare/**` if practical
- [ ] Plan via HCP (`hashicorp/tfc-workflows-github` or `terraform` + API)
- [ ] Apply on `main` + `workflow_dispatch` with Environment `terraform`
- [ ] Secret: `TF_TOKEN_app_terraform_io` (document; do not commit)
- [ ] `ubuntu-latest` runner

### Task 4: Docs touch-up

**Files:**
- Modify: `infrastructure/omni/README.md`, `README.md` (terraform section if present), design already in `docs/plans/`

- [ ] Point operators at HCP workspace + omnictl workers path
- [ ] Note state migrate: `terraform init -migrate-state`

### Task 5: Verify

- [ ] `terraform fmt -check`
- [ ] Confirm no `local-exec` / `data.external` / `omnictl` in `.tf` under `infrastructure/terraform/` (except comments)
- [ ] Workflow YAML parses
