terraform {
  required_version = ">= 1.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.50"
    }
  }

  # Uncomment and configure a remote backend for team use:
  # backend "s3" { ... }     # S3-compatible (MinIO, Cloudflare R2, etc.)
  # backend "http" { ... }   # GitLab-managed state
}

provider "hcloud" {
  token = var.hcloud_token
}
