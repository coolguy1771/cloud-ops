#!/usr/bin/env bash
# Create a dedicated Authentik service account for one M2M tenant, tag it with a
# tenant_id attribute, and make sure the OAuth2 provider exposes that attribute as
# a "tenant_id" scope claim. Used by external M2M hosts (e.g. delilah) pushing to
# Mimir/Loki through the gateway, which maps the token's tenant_id claim to
# X-Scope-OrgID (see kubernetes/apps/istio-ingress/gateway/app/gateway-requestauthentication.yaml).
#
# Why a dedicated account per tenant: with the client_credentials grant, authenticating
# with the PROVIDER's own client_secret always resolves to one shared, auto-generated
# account named "ak-<provider_name>-client_credentials" - fine for a single tenant, but
# every client sharing that secret would get the same tenant_id. A provider can only
# have one client_secret, so multiple tenants under the same provider instead each get
# their own service account + app-password token, and authenticate with:
#   client_id     = the provider's own client_id (shared, same for every tenant)
#   client_secret = base64("<service-account-username>:<app-password-token>")
# Authentik resolves the account from the decoded client_secret, not from client_id.
#
# Prerequisites:
#   export AUTHENTIK_TOKEN=...   # Intent: API Token
#
# Usage:
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-claim.sh --tenant-id icbplays-net --name m2m-icbplays-net
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-claim.sh --tenant-id icbplays-net --name m2m-icbplays-net --provider "Observability M2M"
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-claim.sh --tenant-id icbplays-net --name m2m-icbplays-net --dry-run

set -euo pipefail

AUTHENTIK_URL="${AUTHENTIK_URL:-https://auth.cloud.witl.xyz}"
PROVIDER_NAME="${PROVIDER_NAME:-Observability M2M}"
MAPPING_NAME="${MAPPING_NAME:-OAuth2 tenant_id (from service account attribute)}"
SCOPE_NAME="${SCOPE_NAME:-tenant_id}"
TENANT_ID=""
SA_NAME=""
DRY_RUN=0
ATTACH=1

die() { echo "error: $*" >&2; exit 1; }
log() { echo "$*"; }
urlencode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --dry-run) DRY_RUN=1 ;;
    --no-attach) ATTACH=0 ;;
    --provider=*) PROVIDER_NAME="${args[$i]#--provider=}" ;;
    --tenant-id=*) TENANT_ID="${args[$i]#--tenant-id=}" ;;
    --name=*) SA_NAME="${args[$i]#--name=}" ;;
    --provider)
      [[ -n "${args[$((i + 1))]:-}" ]] && PROVIDER_NAME="${args[$((i + 1))]}"
      ;;
    --tenant-id)
      [[ -n "${args[$((i + 1))]:-}" ]] && TENANT_ID="${args[$((i + 1))]}"
      ;;
    --name)
      [[ -n "${args[$((i + 1))]:-}" ]] && SA_NAME="${args[$((i + 1))]}"
      ;;
    -h|--help)
      echo "Usage: $0 --tenant-id TENANT --name SERVICE_ACCOUNT_NAME [--provider NAME] [--dry-run] [--no-attach]"
      exit 0
      ;;
  esac
done

[[ -n "$TENANT_ID" ]] || die "set --tenant-id (e.g. --tenant-id icbplays-net)"
[[ -n "$SA_NAME" ]] || die "set --name for the dedicated service account (e.g. --name m2m-icbplays-net)"
[[ -n "${AUTHENTIK_TOKEN:-}" ]] || die "set AUTHENTIK_TOKEN (Intent: API Token)"
AUTHENTIK_TOKEN="$(printf '%s' "${AUTHENTIK_TOKEN}" | tr -d '\r\n ')"

api() {
  local method="$1" path="$2" data="${3:-}"
  local url="${AUTHENTIK_URL}/api/v3${path}"
  local tmp code
  tmp="$(mktemp)"
  if [[ -n "$data" ]]; then
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$url" || true)"
  else
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
      -H "Accept: application/json" \
      "$url" || true)"
  fi
  if [[ "$code" != "200" && "$code" != "201" && "$code" != "204" ]]; then
    echo "error: ${method} ${path} -> HTTP ${code}" >&2
    head -c 500 "$tmp" >&2; echo >&2
    rm -f "$tmp"
    exit 1
  fi
  cat "$tmp"
  rm -f "$tmp"
}

log "Authentik: ${AUTHENTIK_URL}"
me="$(api GET "/core/users/me/")"
log "Authenticated as: $(echo "$me" | jq -r '.user.username // .user.email // .username // .email // .user.pk // .pk // "unknown"')"

provider="$(api GET "/providers/oauth2/?page_size=100" \
  | jq -c --arg n "$PROVIDER_NAME" '.results[] | select(.name == $n)')"
[[ -n "$provider" ]] || die "OAuth2 provider '${PROVIDER_NAME}' not found"
provider_pk="$(echo "$provider" | jq -r .pk)"
provider_client_id="$(echo "$provider" | jq -r .client_id)"
log "Provider: ${PROVIDER_NAME} (pk=${provider_pk}, client_id=${provider_client_id})"

existing="$(api GET "/core/users/?username=$(urlencode "$SA_NAME")" | jq -c '.results[0] // empty')"
app_password=""
if [[ -n "$existing" ]]; then
  sa_pk="$(echo "$existing" | jq -r .pk)"
  log "Service account '${SA_NAME}' already exists (pk=${sa_pk}) - not recreating."
  log "Its app-password token isn't retrievable after creation; use the Authentik UI"
  log "(Directory > Tokens and App passwords) to view or rotate it if you've lost it."
  sa="$existing"
else
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would create service account '${SA_NAME}'"
    sa_pk="dry-run-sa"
    sa='{}'
  else
    created="$(api POST "/core/users/service_account/" "$(jq -n --arg name "$SA_NAME" \
      '{name: $name, create_group: false, expiring: false}')")"
    sa_pk="$(echo "$created" | jq -r .user_pk)"
    app_password="$(echo "$created" | jq -r .token)"
    log "Created service account '${SA_NAME}' (pk=${sa_pk})"
    sa="$(api GET "/core/users/${sa_pk}/")"
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "[dry-run] would set attributes.tenant_id=${TENANT_ID} on ${SA_NAME}"
else
  merged_attrs="$(echo "$sa" | jq -c --arg t "$TENANT_ID" '(.attributes // {}) + {tenant_id: $t}')"
  api PATCH "/core/users/${sa_pk}/" "$(jq -n --argjson attrs "$merged_attrs" '{attributes: $attrs}')" >/dev/null
  log "Set attributes.tenant_id=${TENANT_ID} on ${SA_NAME}"
fi

TENANT_EXPR=$'return {\n  "tenant_id": request.user.attributes.get("tenant_id"),\n}'

scope_maps="$(api GET "/propertymappings/provider/scope/?page_size=100")"
mapping_pk="$(echo "$scope_maps" | jq -r --arg n "$MAPPING_NAME" \
  '.results[] | select(.scope_name == "'"$SCOPE_NAME"'" and .name == $n) | .pk' | head -1)"
if [[ -z "$mapping_pk" ]]; then
  mapping_pk="$(echo "$scope_maps" | jq -r --arg s "$SCOPE_NAME" \
    '.results[] | select(.scope_name == $s) | .pk' | head -1)"
fi

if [[ -z "$mapping_pk" ]]; then
  body="$(jq -n \
    --arg name "$MAPPING_NAME" \
    --arg scope "$SCOPE_NAME" \
    --arg expr "$TENANT_EXPR" \
    '{name: $name, scope_name: $scope, expression: $expr}')"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would create scope mapping ${MAPPING_NAME} (scope_name=${SCOPE_NAME})"
    mapping_pk="dry-run-tenant-id"
  else
    mapping_pk="$(api POST "/propertymappings/provider/scope/" "$body" | jq -r .pk)"
    log "Created scope mapping pk=${mapping_pk}"
  fi
else
  log "Scope mapping ${SCOPE_NAME} already exists pk=${mapping_pk}"
fi

if [[ "$ATTACH" -eq 1 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would attach ${SCOPE_NAME} mapping to provider ${PROVIDER_NAME}"
  else
    maps="$(echo "$provider" | jq -c --arg m "$mapping_pk" \
      '((.property_mappings // []) + [$m]) | unique')"
    api PATCH "/providers/oauth2/${provider_pk}/" "$(jq -n --argjson maps "$maps" \
      '{property_mappings: $maps}')" >/dev/null
    log "Attached ${SCOPE_NAME} mapping to provider ${PROVIDER_NAME} (pk=${provider_pk})"
  fi
fi

log ""
if [[ -n "$app_password" ]]; then
  client_secret="$(printf '%s:%s' "$SA_NAME" "$app_password" | base64 | tr -d '\n')"
  log "client_id:     ${provider_client_id}"
  log "client_secret: ${client_secret}"
  log "(This is the only time the app-password token is shown - save client_secret now.)"
else
  log "client_id: ${provider_client_id}"
  log "client_secret: base64(\"${SA_NAME}:<app-password-token>\") - retrieve the token from"
  log "the Authentik UI since this account already existed."
fi
log ""
log "Configure the host's oauth2 block with the client_id/client_secret above and"
log "scopes = [\"mimir:write\", \"loki:write\", \"${SCOPE_NAME}\"] (token_url stays the shared"
log "https://auth.cloud.witl.xyz/application/o/token/)."
log "Done."
