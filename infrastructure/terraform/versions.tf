terraform {
  required_version = ">= 1.6"

  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.50"
    }
    omni = {
      source  = "siderolabs/omni"
      version = "0.1.0-alpha.3"
    }
  }

  # Uncomment and configure a remote backend for team use:
  # backend "s3" { ... }     # S3-compatible (MinIO, Cloudflare R2, etc.)
  # backend "http" { ... }   # GitLab-managed state
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "omni" {
  endpoint             = var.omni_endpoint
  service_account_key  = var.omni_service_account_key
  insecure_skip_tls_verify = var.omni_insecure_skip_tls_verify
}
