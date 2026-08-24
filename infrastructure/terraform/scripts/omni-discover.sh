#!/usr/bin/env bash
# Discover Omni machine IDs for Terraform external data source.
# Reads {"cluster": "..."} from stdin; writes JSON to stdout.
set -euo pipefail

CLUSTER="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["cluster"])')"

CLUSTER_LABEL="omni.sidero.dev/cluster"
ROLE_CP_LABEL="omni.sidero.dev/role-controlplane"

omni_ids() {
  local resource_type="$1"
  local selector="$2"
  omnictl get "$resource_type" -l "$selector" -o yaml 2>/dev/null \
    | awk '/^    id: / {print $2}'
}

CP_IDS="$(omni_ids clustermachines "${CLUSTER_LABEL}=${CLUSTER},${ROLE_CP_LABEL}" \
  | paste -sd, - || true)"

export CP_IDS
python3 -c 'import json, os; print(json.dumps({"control_plane_ids": os.environ.get("CP_IDS", "")}))'
