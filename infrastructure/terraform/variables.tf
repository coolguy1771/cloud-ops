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
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_location" {
  description = "Hetzner location for worker nodes"
  type        = string
  default     = "fsn1"
}
