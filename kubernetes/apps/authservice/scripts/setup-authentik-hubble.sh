#!/usr/bin/env bash
# Bootstrap Authentik OAuth app for Hubble UI (authservice OIDC).
#
# Prerequisites:
#   export AUTHENTIK_TOKEN=...   # Authentik API token
#   export OP_SERVICE_ACCOUNT_TOKEN=...  # optional: write to 1Password
#
# Creates:
#   - OAuth2/OIDC provider + application "hubble"
#   - Redirect URI https://hubble.cloud.witl.xyz/callback
#   - Policy binding to group cloud-ops-admin
#   - 1Password item hubble-oauth (client_id, client_secret) in vault cloud-ops
#
# Usage:
#   ./kubernetes/apps/authservice/scripts/setup-authentik-hubble.sh
#   ./kubernetes/apps/authservice/scripts/setup-authentik-hubble.sh --dry-run

set -euo pipefail

AUTHENTIK_URL="${AUTHENTIK_URL:-https://auth.cloud.witl.xyz}"
VAULT="${VAULT:-cloud-ops}"
GROUP_NAME="${GROUP_NAME:-cloud-ops-admin}"
APP_SLUG="${APP_SLUG:-hubble}"
REDIRECT_URI="${REDIRECT_URI:-https://hubble.cloud.witl.xyz/callback}"
DRY_RUN=0
SKIP_1PASSWORD=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-1password) SKIP_1PASSWORD=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--skip-1password]"
      exit 0
      ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
log() { echo "$*"; }

[[ -n "${AUTHENTIK_TOKEN:-}" ]] || die "set AUTHENTIK_TOKEN"

api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${AUTHENTIK_URL}/api/v3${path}"
  else
    curl -fsS -X "$method" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
      "${AUTHENTIK_URL}/api/v3${path}"
  fi
}

find_pk() {
  local path="$1" jq_expr="$2"
  api GET "${path}?page_size=100" | jq -r ".results[] | select(${jq_expr}) | .pk" | head -1
}

log "Authentik: ${AUTHENTIK_URL}"
log "App slug: ${APP_SLUG}; group: ${GROUP_NAME}; redirect: ${REDIRECT_URI}"

auth_flow="$(find_pk "/flows/instances/" '.slug == "default-provider-authorization-implicit-consent" or .designation == "authorization"')"
[[ -n "$auth_flow" ]] || die "authorization flow not found"
invalidation_flow="$(find_pk "/flows/instances/" '.slug == "default-provider-invalidation-flow" or .designation == "invalidation"')"
[[ -n "$invalidation_flow" ]] || die "invalidation flow not found"
cert_pk="$(api GET "/crypto/certificatekeypairs/?page_size=5" | jq -r '.results[0].pk')"
[[ -n "$cert_pk" && "$cert_pk" != null ]] || die "no certificate key pair found"

group_pk="$(find_pk "/core/groups/" ".name == \"${GROUP_NAME}\"")"
if [[ -z "$group_pk" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would create group ${GROUP_NAME}"
    group_pk="dry-run-group"
  else
    group_pk="$(api POST "/core/groups/" "$(jq -n --arg name "$GROUP_NAME" '{name: $name}')" | jq -r .pk)"
  fi
fi
log "Group pk: ${group_pk}"

# Attach default scope mappings (openid/email/profile/groups) when present.
map_pks="$(api GET "/propertymappings/provider/scope/?page_size=100" \
  | jq -c '[.results[] | select(.scope_name == "openid" or .scope_name == "email" or .scope_name == "profile" or .scope_name == "groups") | .pk]')"
[[ "$(echo "$map_pks" | jq 'length')" -ge 1 ]] || die "no Authentik scope mappings found (openid/email/profile/groups)"
log "Scope mapping pks: ${map_pks}"

provider_pk="$(find_pk "/providers/oauth2/" ".name == \"${APP_SLUG}\"")"
provider_body="$(jq -n \
  --arg name "$APP_SLUG" \
  --arg auth "$auth_flow" \
  --arg inv "$invalidation_flow" \
  --arg cert "$cert_pk" \
  --arg redirect "$REDIRECT_URI" \
  --argjson maps "$map_pks" \
  '{
    name: $name,
    authorization_flow: $auth,
    invalidation_flow: $inv,
    client_type: "confidential",
    include_claims_in_id_token: true,
    signing_key: $cert,
    sub_mode: "user_email",
    redirect_uris: [{matching_mode: "strict", url: $redirect}],
    property_mappings: $maps
  }')"

if [[ -z "$provider_pk" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would create OAuth2 provider ${APP_SLUG}"
    provider_pk="dry-run-provider"
    client_id="dry-run-client-id"
    client_secret="dry-run-client-secret"
  else
    resp="$(api POST "/providers/oauth2/" "$provider_body")"
    provider_pk="$(echo "$resp" | jq -r .pk)"
    client_id="$(echo "$resp" | jq -r .client_id)"
    client_secret="$(echo "$resp" | jq -r .client_secret)"
  fi
else
  log "Provider exists (pk=${provider_pk}); updating mappings/redirect and fetching client_id"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    client_id="existing-client-id"
    client_secret="existing-client-secret"
  else
    api PATCH "/providers/oauth2/${provider_pk}/" "$provider_body" >/dev/null
    resp="$(api GET "/providers/oauth2/${provider_pk}/")"
    client_id="$(echo "$resp" | jq -r .client_id)"
    client_secret="$(echo "$resp" | jq -r .client_secret)"
  fi
fi

app_pk="$(find_pk "/core/applications/" ".slug == \"${APP_SLUG}\"")"
app_body="$(jq -n \
  --arg name "Hubble" \
  --arg slug "$APP_SLUG" \
  --argjson provider "$provider_pk" \
  '{name: $name, slug: $slug, provider: $provider, meta_launch_url: "https://hubble.cloud.witl.xyz"}')"

if [[ -z "$app_pk" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would create application ${APP_SLUG}"
  else
    app_pk="$(api POST "/core/applications/" "$app_body" | jq -r .pk)"
  fi
else
  log "Application exists (pk=${app_pk})"
fi

# Bind group access policy (expression policy: request.user groups contains cloud-ops-admin)
policy_name="hubble-cloud-ops-admin"
policy_pk="$(find_pk "/policies/expression/" ".name == \"${policy_name}\"")"
policy_body="$(jq -n --arg name "$policy_name" --arg group "$GROUP_NAME" \
  '{name: $name, execution_logging: false, expression: ("return ak_is_group_member(request.user, name=\"" + $group + "\")")}')"
if [[ -z "$policy_pk" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would create expression policy ${policy_name}"
  else
    policy_pk="$(api POST "/policies/expression/" "$policy_body" | jq -r .pk)"
  fi
fi

if [[ "$DRY_RUN" -eq 0 && -n "${app_pk}" && -n "${policy_pk}" ]]; then
  # Application policy binding
  existing="$(api GET "/policies/bindings/?target=${app_pk}&page_size=50" | jq -r --arg p "$policy_pk" '.results[] | select(.policy == ($p|tonumber) or .policy == $p) | .pk' | head -1 || true)"
  if [[ -z "$existing" ]]; then
    api POST "/policies/bindings/" "$(jq -n \
      --argjson policy "$policy_pk" \
      --argjson target "$app_pk" \
      --argjson order 0 \
      '{policy: $policy, target: $target, order: $order, enabled: true, timeout: 30}')" >/dev/null
    log "Bound policy ${policy_name} to application"
  else
    log "Policy binding already exists"
  fi
fi

if [[ "$SKIP_1PASSWORD" -eq 0 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would upsert 1Password item hubble-oauth in vault ${VAULT}"
  else
    command -v op >/dev/null || die "op CLI required (or pass --skip-1password)"
    if op item get hubble-oauth --vault "$VAULT" >/dev/null 2>&1; then
      op item edit hubble-oauth --vault "$VAULT" \
        "client_id[text]=${client_id}" \
        "client_secret[password]=${client_secret}" >/dev/null
      log "Updated 1Password item hubble-oauth"
    else
      op item create --category=login --title=hubble-oauth --vault="$VAULT" \
        "client_id[text]=${client_id}" \
        "client_secret[password]=${client_secret}" >/dev/null
      log "Created 1Password item hubble-oauth"
    fi
  fi
fi

log "Done. client_id=${client_id}"
log "Ensure Authentik maps groups into the ID token (Scope Mapping / property mapping)."
