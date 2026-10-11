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
  description = "Operator/home IPs exempt from the geo challenge, bot fight mode and rate limiting (managed WAF still applies)."
  items = [
    { ip = "74.110.253.209", comment = "Home IPv4" },
    { ip = "2600:4040:11a8:ef00::/56", comment = "Home Verizon IPv6 /56 delegation - covers ef02/ef04 rotation" },
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
