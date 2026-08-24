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

variable "zone_custom_firewall_ruleset_id" {
  description = <<-EOT
    Existing zone entry-point ruleset ID for phase http_request_firewall_custom.
    Cloudflare allows only one; discover via:
      ./scripts/import-zone-custom-ruleset.sh
    or GET /zones/$ZONE_ID/rulesets/phases/http_request_firewall_custom/entrypoint
  EOT
  type        = string
}

variable "zone_custom_firewall_name" {
  description = "Display name for the zone custom firewall entry-point ruleset"
  type        = string
  default     = "default"
}

variable "zone_custom_firewall_extra_rules" {
  description = <<-EOT
    Extra custom security rules already on the zone entry-point ruleset.
    Import script writes these to existing_custom_rules.auto.tfvars.json so
    Terraform does not drop dashboard-created rules on apply.
  EOT
  type        = list(any)
  default     = []
}
