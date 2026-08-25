#!/usr/bin/env bash
# Create a dedicated Authentik service account for one M2M tenant, tagged with the
# observability_tenant attribute the existing "Observability tenant_id" scope mapping
# already reads (scope_name "tenant", expression:
#   return {"tenant_id": request.user.attributes.get("observability_tenant", "witl-xyz")}
# ). That mapping is already attached to the Observability M2M provider and already used
# in production by home-ops (cluster "kyak"), so this script does NOT create or attach
# any new scope mapping - it only provisions the account. The gateway maps the resulting
# tenant_id claim to X-Scope-OrgID (see
# kubernetes/apps/istio-ingress/gateway/app/gateway-requestauthentication.yaml).
#
# Why a dedicated account per tenant: with the client_credentials grant, authenticating
# with the PROVIDER's own client_secret always resolves to one shared, auto-generated
# account named "ak-<provider_name>-client_credentials" with no observability_tenant
# attribute set, which is why that shared account (and anything using it) falls through
# to the mapping's "witl-xyz" default. A provider can only have one client_secret, so a
# second tenant needs its own service account + app-password token, authenticating with:
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
ATTRIBUTE_KEY="observability_tenant"
TENANT_ID=""
SA_NAME=""
DRY_RUN=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "$*"; }
urlencode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --dry-run) DRY_RUN=1 ;;
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
      echo "Usage: $0 --tenant-id TENANT --name SERVICE_ACCOUNT_NAME [--provider NAME] [--dry-run]"
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
  log "[dry-run] would set attributes.${ATTRIBUTE_KEY}=${TENANT_ID} on ${SA_NAME}"
else
  merged_attrs="$(echo "$sa" | jq -c --arg k "$ATTRIBUTE_KEY" --arg t "$TENANT_ID" '(.attributes // {}) + {($k): $t}')"
  api PATCH "/core/users/${sa_pk}/" "$(jq -n --argjson attrs "$merged_attrs" '{attributes: $attrs}')" >/dev/null
  log "Set attributes.${ATTRIBUTE_KEY}=${TENANT_ID} on ${SA_NAME}"
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
log "scopes = [\"openid\", \"tenant\", \"mimir:write\", \"loki:write\"] (matching home-ops's"
log "convention), token_url stays https://auth.cloud.witl.xyz/application/o/token/."
log "Done."
