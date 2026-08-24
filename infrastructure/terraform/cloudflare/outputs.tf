output "hetzner_asn_access_rule_id" {
  description = "Cloudflare IP Access Rule ID allowing Hetzner ASN"
  value       = cloudflare_access_rule.hetzner_asn_allow.id
}

output "zone_custom_firewall_ruleset_id" {
  description = "Zone http_request_firewall_custom entry-point ruleset ID"
  value       = cloudflare_ruleset.zone_custom_firewall.id
}
