output "hetzner_asn_access_rule_id" {
  description = "Cloudflare IP Access Rule ID allowing Hetzner ASN"
  value       = cloudflare_access_rule.hetzner_asn_allow.id
}

output "authentik_oidc_ruleset_id" {
  description = "Zone custom ruleset ID for Authentik OIDC skip"
  value       = cloudflare_ruleset.authentik_oidc_skip.id
}
