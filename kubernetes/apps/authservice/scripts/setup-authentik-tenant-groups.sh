#!/usr/bin/env bash
# Create (or update) an Authentik group bound to a tenant_id attribute, add users to it,
# and make sure the shared "Observability tenant_id" scope mapping (scope_name "tenant",
# already attached to the Observability M2M and Grafana OAuth2 providers) aggregates
# tenant_id across a user's groups - so a user in multiple tenant groups gets a
# pipe-delimited X-Scope-OrgID (tenantA|tenantB) on query requests. Service accounts are
# unaffected: their single attributes.observability_tenant value still wins first (see
# setup-authentik-tenant-claim.sh).
#
# Multi-tenant only works on query endpoints - Mimir/Loki both reject a pipe-delimited
# X-Scope-OrgID on push/write regardless of this. Mimir needs tenant_federation.enabled
# and Loki needs limits_config.multi_tenant_queries_enabled for the pipe-delimited header
# to be honored at all (see kubernetes/apps/mimir-system/mimir/app/helmrelease.yaml and
# kubernetes/apps/observability/loki/app/helmrelease.yaml).
#
# Prerequisites:
#   export AUTHENTIK_TOKEN=...   # Intent: API Token
#
# Usage:
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-groups.sh --tenant-id icbplays-net --user alice
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-groups.sh --tenant-id icbplays-net --user alice --user bob --group tenant-icbplays-net
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-groups.sh --tenant-id icbplays-net --user alice --no-update-mapping
#   ./kubernetes/apps/authservice/scripts/setup-authentik-tenant-groups.sh --tenant-id icbplays-net --user alice --dry-run

set -euo pipefail

AUTHENTIK_URL="${AUTHENTIK_URL:-https://auth.cloud.witl.xyz}"
MAPPING_NAME="${MAPPING_NAME:-Observability tenant_id}"
SCOPE_NAME="${SCOPE_NAME:-tenant}"
TENANT_ID=""
GROUP_NAME=""
USERS=()
DRY_RUN=0
UPDATE_MAPPING=1

die() { echo "error: $*" >&2; exit 1; }
log() { echo "$*"; }
urlencode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --dry-run) DRY_RUN=1 ;;
    --no-update-mapping) UPDATE_MAPPING=0 ;;
    --tenant-id=*) TENANT_ID="${args[$i]#--tenant-id=}" ;;
    --group=*) GROUP_NAME="${args[$i]#--group=}" ;;
    --user=*) USERS+=("${args[$i]#--user=}") ;;
    --tenant-id)
      [[ -n "${args[$((i + 1))]:-}" ]] && TENANT_ID="${args[$((i + 1))]}"
      ;;
    --group)
      [[ -n "${args[$((i + 1))]:-}" ]] && GROUP_NAME="${args[$((i + 1))]}"
      ;;
    --user)
      [[ -n "${args[$((i + 1))]:-}" ]] && USERS+=("${args[$((i + 1))]}")
      ;;
    -h|--help)
      echo "Usage: $0 --tenant-id TENANT [--group NAME] [--user USERNAME]... [--no-update-mapping] [--dry-run]"
      exit 0
      ;;
  esac
done

[[ -n "$TENANT_ID" ]] || die "set --tenant-id (e.g. --tenant-id icbplays-net)"
[[ -n "${AUTHENTIK_TOKEN:-}" ]] || die "set AUTHENTIK_TOKEN (Intent: API Token)"
AUTHENTIK_TOKEN="$(printf '%s' "${AUTHENTIK_TOKEN}" | tr -d '\r\n ')"
GROUP_NAME="${GROUP_NAME:-tenant-${TENANT_ID}}"

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
log "Authenticated as: $(echo "$me" | jq -r '.user.username // .user.email // .username // .email // "unknown"')"

group="$(api GET "/core/groups/?name=$(urlencode "$GROUP_NAME")" | jq -c '.results[0] // empty')"
if [[ -n "$group" ]]; then
  group_pk="$(echo "$group" | jq -r .pk)"
  log "Group '${GROUP_NAME}' already exists (pk=${group_pk})"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would set attributes.tenant_id=${TENANT_ID} on ${GROUP_NAME}"
  else
    merged_attrs="$(echo "$group" | jq -c --arg t "$TENANT_ID" '(.attributes // {}) + {tenant_id: $t}')"
    api PATCH "/core/groups/${group_pk}/" "$(jq -n --argjson attrs "$merged_attrs" '{attributes: $attrs}')" >/dev/null
    log "Set attributes.tenant_id=${TENANT_ID} on ${GROUP_NAME}"
  fi
else
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would create group '${GROUP_NAME}' with attributes.tenant_id=${TENANT_ID}"
    group_pk="dry-run-group"
  else
    created="$(api POST "/core/groups/" "$(jq -n --arg name "$GROUP_NAME" --arg t "$TENANT_ID" \
      '{name: $name, attributes: {tenant_id: $t}}')")"
    group_pk="$(echo "$created" | jq -r .pk)"
    log "Created group '${GROUP_NAME}' (pk=${group_pk}) with attributes.tenant_id=${TENANT_ID}"
  fi
fi

for username in "${USERS[@]:-}"; do
  [[ -n "$username" ]] || continue
  user="$(api GET "/core/users/?username=$(urlencode "$username")" | jq -c '.results[0] // empty')"
  [[ -n "$user" ]] || { log "warning: no user found with username '${username}', skipping"; continue; }
  user_pk="$(echo "$user" | jq -r .pk)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] would add ${username} (pk=${user_pk}) to ${GROUP_NAME}"
  else
    api POST "/core/groups/${group_pk}/add_user/" "$(jq -n --argjson pk "$user_pk" '{pk: $pk}')" >/dev/null
    log "Added ${username} to ${GROUP_NAME}"
  fi
done

if [[ "$UPDATE_MAPPING" -eq 0 ]]; then
  log "Done (mapping expression left untouched)."
  exit 0
fi

GROUP_AGGREGATE_EXPR=$'tenant_ids = [\n    g.attributes.get("tenant_id")\n    for g in request.user.ak_groups.all()\n    if g.attributes.get("tenant_id")\n]\nreturn {\n    "tenant_id": (\n        request.user.attributes.get("observability_tenant")\n        or "|".join(sorted(set(tenant_ids)))\n        or "witl-xyz"\n    ),\n}'

mapping="$(api GET "/propertymappings/provider/scope/?page_size=100" \
  | jq -c --arg n "$MAPPING_NAME" --arg s "$SCOPE_NAME" \
    '.results[] | select(.name == $n and .scope_name == $s)')"
[[ -n "$mapping" ]] || die "scope mapping '${MAPPING_NAME}' (scope_name=${SCOPE_NAME}) not found - expected it to already exist from prior M2M setup"
mapping_pk="$(echo "$mapping" | jq -r .pk)"
current_expr="$(echo "$mapping" | jq -r .expression)"

if [[ "$current_expr" == "$GROUP_AGGREGATE_EXPR" ]]; then
  log "Mapping '${MAPPING_NAME}' already aggregates across groups - nothing to update."
elif [[ "$DRY_RUN" -eq 1 ]]; then
  log "[dry-run] would update mapping '${MAPPING_NAME}' (pk=${mapping_pk}) to aggregate tenant_id across groups"
else
  api PATCH "/propertymappings/provider/scope/${mapping_pk}/" "$(jq -n --arg expr "$GROUP_AGGREGATE_EXPR" '{expression: $expr}')" >/dev/null
  log "Updated mapping '${MAPPING_NAME}' (pk=${mapping_pk}) to aggregate tenant_id across a user's groups"
fi

log "Done."
