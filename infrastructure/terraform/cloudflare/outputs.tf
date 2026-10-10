output "zone_custom_firewall_ruleset_id" {
  description = "Zone http_request_firewall_custom entry-point ruleset ID"
  value       = cloudflare_ruleset.zone_custom_firewall.id
}

output "list_ids" {
  description = "Account IP list IDs referenced by the WAF rules"
  value = {
    manual_blocklist = cloudflare_list.manual_blocklist.id
    telemetry_nodes  = cloudflare_list.telemetry_nodes.id
    trusted_ips      = cloudflare_list.trusted_ips.id
  }
}
