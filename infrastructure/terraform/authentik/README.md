# authentik (Terraform)

Source of truth for authentik configuration at `https://auth.cloud.witl.xyz`:
providers, applications, groups, observability tenants and M2M service accounts,
access policy, the LDAP outpost, and login-flow hardening.

This replaces:
- the `authentik-security-hardening-blueprint` ConfigMap (it never applied: blueprints are
  atomic and one entry failed validation)
- `kubernetes/apps/authservice/scripts/setup-authentik-tenant-{claim,groups}.sh`
- changes made by hand in the admin UI

Objects created by authentik's shipped default blueprints (default flows, consent flows,
built-in scope mappings, the self-signed certificate) are read with data sources, not
managed. Exception: a few default stages and the password policy are managed so they can
be hardened (see `flows.tf`).

## HCP Terraform workspace

| Setting | Value |
|---|---|
| Organization / workspace | `coolguy1771` / `cloud-ops-authentik` |
| Working directory | `infrastructure/terraform/authentik` |
| Variable `authentik_token` (sensitive) | API token `terraform-api` of the `terraform` service account (member of `authentik Admins`) |
| Variable `turnstile_secret_key` (sensitive) | Secret key of the Turnstile widget for site key `0x4AAAAAAEptAcIx8ho82YFk` (Cloudflare dashboard > Turnstile) |

## First apply

`imports.tf` adopts the existing objects. The first plan should show **70 to import,
3 to add, 9 to change, 0 to destroy**. The changes are intentional:

- MFA is enforced: users without a device must enroll (WebAuthn, TOTP or static codes)
  at their next login, and WebAuthn user verification is required.
- Password policy: 15 characters minimum, plus a HaveIBeenPwned check (applies on
  password change).
- Login no longer reveals whether an identifier matched an account; a new login ends
  the user's other sessions; no long-lived "remember device" cookie.
- Hubble is gated to `cloud-ops-admin` (the policy existed but was never bound).
- The LDAP flow gets its own login stage, so UniFi binds don't end web sessions.
- Duplicate redirect URI and grant types on Level are removed.

Delete `imports.tf` once the first apply has succeeded.

## Adding an observability tenant

- **Humans:** add `"<tenant_id>" = ["<username>", ...]` to `local.observability_tenants`
  in `access.tf`. Their `tenant` claim becomes the pipe-joined list of their tenants,
  which works on query endpoints only.
- **M2M:** add `"<service-account>" = { tenant = "<tenant_id>", create_token = true }`
  to `local.m2m_service_accounts`, apply, then read the client secret:

  ```sh
  terraform output -raw observability_m2m_client_id
  terraform output -json m2m_client_secrets | jq -r '."<service-account>"'
  ```

  Clients use scopes `openid tenant mimir:write loki:write` against
  `https://auth.cloud.witl.xyz/application/o/token/`.
