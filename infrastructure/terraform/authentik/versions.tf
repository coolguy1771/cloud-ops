terraform {
  required_version = ">= 1.6"

  cloud {
    organization = "coolguy1771"

    workspaces {
      name = "cloud-ops-authentik"
    }
  }

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.8.0"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
