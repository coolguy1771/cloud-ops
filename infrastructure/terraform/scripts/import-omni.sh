#!/usr/bin/env bash
# Import existing Omni resources into Terraform state.
# Discovers cluster, machine sets, machines, and config patches via omnictl labels.
#
# Run from infrastructure/terraform after: terraform init && configuring tfvars/auth.
#
# Usage:
#   omnictl serviceaccount create --use-user-role=false --role Admin terraform
#   export OMNI_SERVICE_ACCOUNT_KEY="<base64-key-from-output>"
#   export OMNI_ENDPOINT="https://your-instance.omni.siderolabs.io"  # optional if in tfvars/omnictl
#   ./scripts/import-omni.sh
#
# Override cluster: CLUSTER_NAME=my-cluster ./scripts/import-omni.sh
#
# Safe to re-run — skips resources already in state.

set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER_LABEL="omni.sidero.dev/cluster"
ROLE_CP_LABEL="omni.sidero.dev/role-controlplane"
ROLE_WORKER_LABEL="omni.sidero.dev/role-worker"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

resolve_cluster_name() {
  if [[ -n "${CLUSTER_NAME:-}" ]]; then
    echo "$CLUSTER_NAME"
    return
  fi

  if [[ -f terraform.tfvars ]]; then
    local from_tfvars
    from_tfvars="$(
      grep -E '^[[:space:]]*cluster_name[[:space:]]*=' terraform.tfvars \
        | head -1 \
        | sed -E 's/^[[:space:]]*cluster_name[[:space:]]*=[[:space:]]*"?([^"#]+)"?.*/\1/' \
        | tr -d '[:space:]' \
        || true
    )"
    if [[ -n "$from_tfvars" ]]; then
      echo "$from_tfvars"
      return
    fi
  fi

  echo "cloud-ops"
}

resolve_omni_endpoint() {
  if [[ -n "${OMNI_ENDPOINT:-}" ]]; then
    echo "$OMNI_ENDPOINT"
    return
  fi

  if [[ -f terraform.tfvars ]]; then
    local from_tfvars
    from_tfvars="$(
      grep -E '^[[:space:]]*omni_endpoint[[:space:]]*=' terraform.tfvars \
        | head -1 \
        | sed -E 's/^[[:space:]]*omni_endpoint[[:space:]]*=[[:space:]]*"?([^"#]+)"?.*/\1/' \
        | tr -d '[:space:]' \
        || true
    )"
    if [[ -n "$from_tfvars" ]]; then
      echo "$from_tfvars"
      return
    fi
  fi

  omnictl config info 2>/dev/null \
    | awk -F':[[:space:]]+' '/^URL:/ {print $2; exit}'
}

check_terraform_omni_auth() {
  if [[ -z "${OMNI_SERVICE_ACCOUNT_KEY:-}" ]]; then
    cat >&2 <<'EOF'
error: Terraform requires OMNI_SERVICE_ACCOUNT_KEY.

omnictl user login is not enough for terraform import/plan — the provider uses a
service account key, not your interactive Omni session.

Create one (while logged in via omnictl):
  omnictl serviceaccount create --use-user-role=false --role Admin terraform

Export the base64 key from the command output:
  export OMNI_SERVICE_ACCOUNT_KEY="<base64-key>"
EOF
    exit 1
  fi

  if ! python3 -c "import base64, os; base64.b64decode(os.environ['OMNI_SERVICE_ACCOUNT_KEY'], validate=True)" 2>/dev/null; then
    echo "error: OMNI_SERVICE_ACCOUNT_KEY is not valid base64" >&2
    exit 1
  fi
}

export_terraform_omni_env() {
  local endpoint="$1"
  export OMNI_ENDPOINT="$endpoint"
  export TF_VAR_omni_endpoint="$endpoint"
}

omni_resource_ids() {
  local resource_type="$1"
  shift
  omnictl get "$resource_type" "$@" -o yaml 2>/dev/null \
    | awk '/^    id: / {print $2}'
}

discover_machine_set() {
  local cluster="$1"
  local role_label="$2"
  local ids
  ids="$(omni_resource_ids machinesets \
    -l "${CLUSTER_LABEL}=${cluster},${role_label}")"

  if [[ -z "$ids" ]]; then
    echo "error: no machine set for cluster=${cluster} label=${role_label}" >&2
    exit 1
  fi

  if [[ "$(echo "$ids" | wc -l | tr -d ' ')" -gt 1 ]]; then
    echo "error: multiple machine sets for label=${role_label}: ${ids//$'\n'/, }" >&2
    exit 1
  fi

  echo "$ids"
}

discover_cluster_machines() {
  local cluster="$1"
  local role_label="$2"
  omni_resource_ids clustermachines \
    -l "${CLUSTER_LABEL}=${cluster},${role_label}"
}

discover_config_patch_id() {
  local cluster="$1"
  local id_pattern="$2"
  local ids
  ids="$(omni_resource_ids configpatches \
    -l "${CLUSTER_LABEL}=${cluster}" \
    --id-match-regexp "$id_pattern")"

  if [[ -z "$ids" ]]; then
    echo "error: no config patch matching /${id_pattern}/ for cluster=${cluster}" >&2
    exit 1
  fi

  if [[ "$(echo "$ids" | wc -l | tr -d ' ')" -gt 1 ]]; then
    echo "error: multiple config patches matching /${id_pattern}/: ${ids//$'\n'/, }" >&2
    exit 1
  fi

  echo "$ids"
}

machine_id_from_install_patch() {
  sed -E 's/^000-cm-(.+)-install-disk$/\1/'
}

import_if_missing() {
  local addr="$1"
  local id="$2"
  if terraform state show "$addr" &>/dev/null; then
    echo "skip  $addr (already in state)"
  else
    echo "import $addr <= $id"
    terraform import -input=false "$addr" "$id"
  fi
}

require_cmd omnictl
require_cmd terraform
require_cmd awk
require_cmd python3

OMNI_ENDPOINT_RESOLVED="$(resolve_omni_endpoint)"
if [[ -z "$OMNI_ENDPOINT_RESOLVED" ]]; then
  echo "error: could not resolve Omni endpoint (set OMNI_ENDPOINT or omni_endpoint in terraform.tfvars)" >&2
  exit 1
fi

export_terraform_omni_env "$OMNI_ENDPOINT_RESOLVED"
check_terraform_omni_auth

CLUSTER="$(resolve_cluster_name)"
SELECTOR="${CLUSTER_LABEL}=${CLUSTER}"

echo "==> Omni API: ${OMNI_ENDPOINT_RESOLVED}"
echo "==> Discovering resources (cluster=${CLUSTER})"

if ! omnictl get clusters "$CLUSTER" >/dev/null 2>&1; then
  echo "error: cluster '${CLUSTER}' not found in Omni" >&2
  exit 1
fi

CP_SET="$(discover_machine_set "$CLUSTER" "$ROLE_CP_LABEL")"
WORKER_SET="$(discover_machine_set "$CLUSTER" "$ROLE_WORKER_LABEL")"

mapfile -t CP_MACHINES < <(discover_cluster_machines "$CLUSTER" "$ROLE_CP_LABEL")
mapfile -t WORKER_MACHINES < <(discover_cluster_machines "$CLUSTER" "$ROLE_WORKER_LABEL")

ALL_NODES_PATCH="$(discover_config_patch_id "$CLUSTER" 'all-nodes')"
CONTROL_PLANE_PATCH="$(discover_config_patch_id "$CLUSTER" 'controlplane')"

mapfile -t INSTALL_DISK_PATCHES < <(
  omni_resource_ids configpatches \
    -l "${SELECTOR}" \
    --id-match-regexp 'install-disk$'
)

echo "    control plane set: ${CP_SET}"
echo "    worker set:        ${WORKER_SET}"
echo "    control plane nodes: ${#CP_MACHINES[@]}"
echo "    worker nodes:        ${#WORKER_MACHINES[@]}"
echo "    install-disk patches: ${#INSTALL_DISK_PATCHES[@]}"

if [[ ${#CP_MACHINES[@]} -eq 0 || ${#WORKER_MACHINES[@]} -eq 0 ]]; then
  echo "error: expected at least one control plane and worker machine" >&2
  exit 1
fi

echo "==> Cluster and machine sets"
import_if_missing omni_cluster.this "$CLUSTER"
import_if_missing omni_machine_set.control_plane "$CP_SET"
import_if_missing omni_machine_set.workers "$WORKER_SET"

echo "==> Control plane nodes"
for id in "${CP_MACHINES[@]}"; do
  import_if_missing "omni_machine_set_node.control_plane[\"$id\"]" "$id"
done

echo "==> Worker nodes"
for id in "${WORKER_MACHINES[@]}"; do
  import_if_missing "omni_machine_set_node.worker[\"$id\"]" "$id"
done

echo "==> Config patches"
import_if_missing omni_config_patch.all_nodes "$ALL_NODES_PATCH"
import_if_missing omni_config_patch.control_plane "$CONTROL_PLANE_PATCH"

for patch_id in "${INSTALL_DISK_PATCHES[@]}"; do
  machine_id="$(echo "$patch_id" | machine_id_from_install_patch)"
  if [[ -z "$machine_id" || "$machine_id" == "$patch_id" ]]; then
    echo "error: cannot parse machine id from patch id: ${patch_id}" >&2
    exit 1
  fi
  import_if_missing "omni_config_patch.install_disk[\"${machine_id}\"]" "$patch_id"
done

echo
echo "Done. Run: terraform plan"
echo "Expect minor patch diffs if patch YAML changed — review before apply."
