variable "cloudflare_api_token" {
  description = <<-EOT
    Cloudflare API token (optional if CLOUDFLARE_API_TOKEN is set). Required permissions:
      - Zone → Zone → Read (zone cloud.witl.xyz)
      - Zone → WAF → Edit
      - Account → Account Firewall Access Rules → Edit
    The external-dns dns-token is NOT sufficient (DNS-only). Prefer a dedicated
    1Password field e.g. cloudflare.waf-token.
  EOT
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for cloud.witl.xyz (same as CF_ZONE_ID / 1Password cloudflare.zone-id)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (1Password cloudflare.account_tag). Used for account-scoped IP Access rules so all zones inherit the Hetzner ASN allow."
  type        = string
}

variable "authentik_host" {
  description = "Public Authentik hostname (OIDC discovery / token endpoints)"
  type        = string
  default     = "auth.cloud.witl.xyz"
}

variable "hetzner_asn" {
  description = "Hetzner Online ASN — cluster node egress. Required to bypass Bot Fight Mode (WAF Skip cannot)."
  type        = string
  default     = "24940"
}
