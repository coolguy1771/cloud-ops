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
  description = "Hetzner server type for control plane nodes"
  type        = string
  default     = "cx32"
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

# --- Workers ---
variable "worker_server_type" {
  description = "Hetzner server type for worker nodes"
  type        = string
  default     = "cx32"
}

variable "worker_count" {
  description = "Number of Hetzner worker nodes to provision"
  type        = number
  default     = 7
}

variable "worker_location" {
  description = "Hetzner location for worker nodes"
  type        = string
  default     = "fsn1"
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
