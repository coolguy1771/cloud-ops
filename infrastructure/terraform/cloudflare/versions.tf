terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  # Uses var when set; otherwise CLOUDFLARE_API_TOKEN from the environment.
  api_token = var.cloudflare_api_token
}
