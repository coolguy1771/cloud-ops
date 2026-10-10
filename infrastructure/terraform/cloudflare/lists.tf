# Account-scoped IP lists referenced by the zone custom firewall rules (waf.tf).
# Edit list membership here, not in rule expressions.

resource "cloudflare_list" "manual_blocklist" {
  account_id  = var.cloudflare_account_id
  name        = "manual_blocklist"
  kind        = "ip"
  description = "Manually banned IPs/CIDRs. Blocked at position 1 of custom rules."
  items       = []
}

resource "cloudflare_list" "trusted_ips" {
  account_id  = var.cloudflare_account_id
  name        = "trusted_ips"
  kind        = "ip"
  description = "Operator/home IPs exempt from geo, bot, managed WAF and rate limiting."
  items = [
    { ip = "74.110.253.209", comment = "Home IPv4" },
    { ip = "2600:4040:11a8:ef00::/56", comment = "Home Verizon IPv6 /56 delegation - covers ef02/ef04 rotation" },
  ]
}

resource "cloudflare_list" "telemetry_nodes" {
  account_id  = var.cloudflare_account_id
  name        = "telemetry_nodes"
  kind        = "ip"
  description = "Static-IP machine clients (Alloy agents) allowed to skip WAF on telemetry/OIDC hosts. cloud-ops egress is matched by ASN instead."
  items = [
    { ip = "136.61.29.147", comment = "Alloy agent pushing to loki/mimir/tempo" },
    { ip = "2604:2dc0:100:338c::/64", comment = "OVH node - Alloy agent (AS16276)" },
  ]
}

import {
  to = cloudflare_list.manual_blocklist
  id = "${var.cloudflare_account_id}/3e6f0300c66c4e998a8b89cdd51f1b3f"
}

import {
  to = cloudflare_list.trusted_ips
  id = "${var.cloudflare_account_id}/03d58a49d9c64cdb85ba52c55e67eb22"
}

import {
  to = cloudflare_list.telemetry_nodes
  id = "${var.cloudflare_account_id}/733a2d9561c149828e37a10eb1873d5d"
}
