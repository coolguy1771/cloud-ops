terraform {
  required_version = ">= 1.6"

  cloud {
    organization = "home-ops"

    workspaces {
      project = "cloud-ops"
      name    = "cloud-ops"
    }
  }

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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "omni" {
  endpoint                 = var.omni_endpoint
  service_account_key      = var.omni_service_account_key
  insecure_skip_tls_verify = var.omni_insecure_skip_tls_verify
}
