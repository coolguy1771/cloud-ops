output "hetzner_asn_access_rule_id" {
  description = "Cloudflare IP Access Rule ID allowing Hetzner ASN"
  value       = cloudflare_access_rule.hetzner_asn_allow.id
}
