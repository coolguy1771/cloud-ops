variable "hcloud_token" {
  description = "Hetzner Cloud API token (read/write scope required)"
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Cluster name — used for resource names, labels, and the Omni cluster template"
  type        = string
  default     = "cloud-ops"
}

# --- Image ---
# Download the Omni Talos image from: Omni portal → Add Machine → Download Installation Media → Hetzner
# Upload it to Hetzner with Packer (see infrastructure/terraform/packer/) or hcloud-upload-image,
# then set this to the resulting snapshot ID.
variable "talos_image_id" {
  description = "Hetzner snapshot ID of the Omni-registered Talos image (must be Talos v1.13.x for K8s 1.36.x)"
  type        = string
}

# --- Network ---
variable "network_zone" {
  description = "Hetzner network zone"
  type        = string
  default     = "eu-central"
}

variable "network_ip_range" {
  description = "CIDR for the Hetzner private network"
  type        = string
  default     = "10.0.0.0/8"
}

variable "subnet_ip_range" {
  description = "CIDR for the private subnet (must be within network_ip_range)"
  type        = string
  default     = "10.0.1.0/24"
}

# --- Control Plane ---
variable "control_plane_server_type" {
  description = "Hetzner server type for all control plane nodes when control_plane_server_types is unset"
  type        = string
  default     = "cx33"
}

# Prefer this for rolling resizes (set one index at a time). When set, it
# overrides control_plane_server_type per node.
variable "control_plane_server_types" {
  description = "Per-index Hetzner server types for the three control plane nodes"
  type        = list(string)
  default     = null
  nullable    = true

  validation {
    condition     = var.control_plane_server_types == null || length(var.control_plane_server_types) == 3
    error_message = "Exactly 3 control plane server types required when control_plane_server_types is set."
  }
}

# Spread across two locations for HA; third node re-uses the primary location.
variable "control_plane_locations" {
  description = "Hetzner locations for the three control plane nodes"
  type        = list(string)
  default     = ["fsn1", "nbg1", "fsn1"]

  validation {
    condition     = length(var.control_plane_locations) == 3
    error_message = "Exactly 3 control plane locations required for HA etcd quorum."
  }
}

# Talos machine UUIDs for the control-plane machine set. Required for HCP SaaS
# remote runs (no omnictl discovery). Get via `omnictl get machinestatuses -o yaml`
# and cross-reference network.hostname with hcloud_server.control_plane names.
variable "control_plane_machine_ids" {
  description = "Talos machine UUIDs assigned to the control-plane machine set"
  type        = list(string)
  default     = []
}

# --- Workers ---
# Workers are provisioned dynamically by the Hetzner Omni infra provider (see
# hetzner_infra_provider.tf) via a MachineClass applied with omnictl from
# infrastructure/omni/workers/ — these variables configure the fsn1
# omni_machine_set.workers size and must stay in sync with the YAML.
variable "worker_server_type" {
  description = "Hetzner server type for dynamically auto-provisioned worker nodes (document in omni/workers YAML)"
  type        = string
  default     = "cpx32"
}

variable "worker_locations" {
  description = "Map of Hetzner location -> worker count. One MachineClass and one omni_machine_set is created per location (ignored per-location if worker_allocation_type is Unlimited, in which case the count is just the initial/minimum size)."
  type        = map(number)
  default = {
    fsn1 = 7
  }

  validation {
    condition     = length(var.worker_locations) > 0
    error_message = "worker_locations must have at least one entry."
  }
}

variable "worker_allocation_type" {
  description = "Allocation type for the worker machine class: Static (exact size, worker_count) or Unlimited (autoscale to cluster demand)"
  type        = string
  default     = "Static"

  validation {
    condition     = contains(["Static", "Unlimited"], var.worker_allocation_type)
    error_message = "worker_allocation_type must be \"Static\" or \"Unlimited\"."
  }
}

# --- Omni ---
variable "omni_endpoint" {
  description = "Omni API endpoint. Prefer OMNI_ENDPOINT env var or omnictl context URL."
  type        = string
  default     = null
  nullable    = true
}

variable "omni_service_account_key" {
  description = "Base64-encoded Omni service account key (from `omnictl serviceaccount create`). Prefer OMNI_SERVICE_ACCOUNT_KEY env var."
  type        = string
  sensitive   = true
  default     = null
}

variable "omni_insecure_skip_tls_verify" {
  description = "Skip TLS verification for the Omni endpoint (development only)"
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Kubernetes version for the Omni cluster (semver, no v prefix)"
  type        = string
  default     = "1.36.1"
}

variable "talos_version" {
  description = "Talos version for the Omni cluster (semver, no v prefix)"
  type        = string
  default     = "1.13.7"
}

# --- Hetzner Omni Infra Provider ---
# See hetzner_infra_provider.tf. The daemon (github.com/coolguy1771/hetzner-infra-provider)
# runs outside this repo; Terraform only defines the MachineClass and the
# machine set that draws from it.

variable "hetzner_infra_provider_id" {
  description = "ID the omni-infra-provider-hetzner daemon is registered under in Omni (must match its --id flag, and the `omnictl infraprovider create <id>` used to register it)"
  type        = string
  default     = "hetzner"
}
