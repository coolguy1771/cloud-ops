#!/usr/bin/env bash
# Create an Authentik OIDC scope mapping that emits a "tenant_id" claim from the
# client_credentials service account's attributes, and attach it to an OAuth2 provider.
# Used by external M2M hosts (e.g. delilah) pushing to Mimir/Loki through the gateway,
# which maps the token's tenant_id claim to X-Scope-OrgID (see
# kubernetes/apps/istio-ingress/gateway/app/gateway-requestauthentication.yaml).
#
# With the client_credentials grant, Authentik authenticates against the provider's
# shared client_secret and auto-creates (or reuses) ONE service account per provider
# named "ak-<provider_name>-client_credentials" - every client using that provider's
# secret shares that account and therefore the same tenant_id. That's fine when every
# client of a given provider belongs to one tenant (e.g. all of icbplays-net's hosts);
# it does NOT differentiate tenants within a single provider. For that, create a
# separate OAuth2 provider (and application) per tenant, or a dedicated service account
# per client with its own app-password token as client_secret.
#
# Prerequisites:
#   export AUTHENTIK_TOKEN=...   # Intent: API Token
#
# Usage:
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-claim.sh --tenant-id icbplays-net
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-claim.sh --tenant-id icbplays-net --provider observability-m2m
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-claim.sh --tenant-id icbplays-net --dry-run

set -euo pipefail

AUTHENTIK_URL="${AUTHENTIK_URL:-https://auth.cloud.witl.xyz}"
PROVIDER_NAME="${PROVIDER_NAME:-Observability M2M}"
MAPPING_NAME="${MAPPING_NAME:-OAuth2 tenant_id (from service account attribute)}"
SCOPE_NAME="${SCOPE_NAME:-tenant_id}"
TENANT_ID=""
SERVICE_ACCOUNT=""
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
    --provider)
      TENANT_ID_NEXT=0
      [[ -n "${args[$((i + 1))]:-}" ]] && PROVIDER_NAME="${args[$((i + 1))]}"
      ;;
    --tenant-id)
      [[ -n "${args[$((i + 1))]:-}" ]] && TENANT_ID="${args[$((i + 1))]}"
      ;;
    --service-account=*) SERVICE_ACCOUNT="${args[$i]#--service-account=}" ;;
    --service-account)
      [[ -n "${args[$((i + 1))]:-}" ]] && SERVICE_ACCOUNT="${args[$((i + 1))]}"
      ;;
    -h|--help)
      echo "Usage: $0 --tenant-id TENANT [--provider NAME] [--service-account USERNAME] [--dry-run] [--no-attach]"
      exit 0
      ;;
  esac
done

[[ -n "$TENANT_ID" ]] || die "set --tenant-id (e.g. --tenant-id icbplays-net)"
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
log "Provider: ${PROVIDER_NAME} (pk=${provider_pk})"

if [[ -n "$SERVICE_ACCOUNT" ]]; then
  sa="$(api GET "/core/users/?username=$(urlencode "$SERVICE_ACCOUNT")" | jq -c '.results[0] // empty')"
  [[ -n "$sa" ]] || die "no user found with username '${SERVICE_ACCOUNT}'"
else
  # The client_credentials service account is auto-named ak-<provider_name>-client_credentials
  # with authentik's own slug transform, which we don't try to replicate - search broadly for
  # every auto-generated client_credentials account instead and match against the provider name.
  candidates="$(api GET "/core/users/?search=$(urlencode "client_credentials")&page_size=100")"
  sa="$(echo "$candidates" | jq -c --arg p "$PROVIDER_NAME" \
    '[.results[] | select(.username | test("client_credentials$"))] as $all
     | ($all | map(select(.username | ascii_downcase | contains($p | ascii_downcase | gsub(" "; "-"))))) as $matched
     | if ($matched | length) == 1 then $matched[0]
       elif ($all | length) == 1 then $all[0]
       else empty end')"
  if [[ -z "$sa" ]]; then
    log "Could not uniquely identify the service account. Candidates found:"
    echo "$candidates" | jq -r '.results[] | select(.username | test("client_credentials$")) | "  " + .username' >&2
    die "pass --service-account USERNAME to pick one (or run the provider once with its client_secret first so authentik auto-creates it)."
  fi
fi
sa_pk="$(echo "$sa" | jq -r .pk)"
sa_username="$(echo "$sa" | jq -r .username)"
log "Service account: ${sa_username} (pk=${sa_pk})"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "[dry-run] would set attributes.tenant_id=${TENANT_ID} on ${sa_username}"
else
  merged_attrs="$(echo "$sa" | jq -c --arg t "$TENANT_ID" '(.attributes // {}) + {tenant_id: $t}')"
  api PATCH "/core/users/${sa_pk}/" "$(jq -n --argjson attrs "$merged_attrs" '{attributes: $attrs}')" >/dev/null
  log "Set attributes.tenant_id=${TENANT_ID} on ${sa_username}"
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

if [[ "$ATTACH" -eq 0 ]]; then
  log "Done (not attaching to provider)."
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "[dry-run] would attach ${SCOPE_NAME} mapping to provider ${PROVIDER_NAME}"
  exit 0
fi

maps="$(echo "$provider" | jq -c --arg m "$mapping_pk" \
  '((.property_mappings // []) + [$m]) | unique')"
api PATCH "/providers/oauth2/${provider_pk}/" "$(jq -n --argjson maps "$maps" \
  '{property_mappings: $maps}')" >/dev/null
log "Attached ${SCOPE_NAME} mapping to provider ${PROVIDER_NAME} (pk=${provider_pk})"
log ""
log "Clients authenticating against this provider must now request scope '${SCOPE_NAME}'"
log "alongside their other scopes, e.g. scopes = [\"mimir:write\", \"loki:write\", \"${SCOPE_NAME}\"]."
log "Every client using this provider's shared client_secret shares this service account,"
log "so they all get tenant_id=${TENANT_ID}. Use a separate provider for a different tenant."
log "Done."
