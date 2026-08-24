# Bot Fight Mode cannot be skipped via WAF custom rules. An IP Access Rule
# Allow matching first is the supported exception path for Free/Pro BFM.
# https://developers.cloudflare.com/bots/get-started/bot-fight-mode/
resource "cloudflare_access_rule" "hetzner_asn_allow" {
  account_id = var.cloudflare_account_id
  mode       = "whitelist"
  notes      = "Hetzner Cloud ASN — allow cluster egress (Kiali/Authentik OIDC machine clients); bypasses Bot Fight Mode"
  configuration = {
    target = "asn"
    value  = var.hetzner_asn
  }
}

locals {
  # Zone security rule (custom WAF): skip managed/SBFM/ratelimit for Authentik OIDC.
  # Does NOT skip Bot Fight Mode — that needs the ASN IP Access Rule above.
  authentik_oidc_skip_rule = {
    ref         = "skip_authentik_oidc_endpoints"
    description = "Skip WAF/SBFM/ratelimit for Authentik OIDC endpoints"
    enabled     = true
    action      = "skip"
    expression  = <<-EOT
      (http.host eq "${var.authentik_host}" and (
        ends_with(http.request.uri.path, "/.well-known/openid-configuration") or
        starts_with(http.request.uri.path, "/application/o/token") or
        starts_with(http.request.uri.path, "/application/o/userinfo") or
        ends_with(http.request.uri.path, "/jwks/") or
        http.request.uri.path contains "/jwks/"
      ))
    EOT
    action_parameters = {
      phases = [
        "http_request_firewall_managed",
        "http_request_sbfm",
        "http_ratelimit",
      ]
      products = [
        "bic",
        "hot",
        "securityLevel",
        "uaBlock",
        "rateLimit",
        "waf",
        "zoneLockdown",
      ]
      ruleset = "current"
    }
  }

  # Skip first so later custom rules do not override for OIDC paths.
  zone_custom_firewall_rules = concat(
    [local.authentik_oidc_skip_rule],
    var.zone_custom_firewall_extra_rules,
  )
}

# Zone has exactly one entry-point ruleset for http_request_firewall_custom.
# Creating a second fails with API 20217 — import the existing one first:
#
#   ./scripts/import-zone-custom-ruleset.sh
#
# Import ID format (provider v5): zones/<zone_id>/<ruleset_id>
resource "cloudflare_ruleset" "zone_custom_firewall" {
  zone_id     = var.cloudflare_zone_id
  name        = var.zone_custom_firewall_name
  description = "Zone custom security rules (managed by Terraform)"
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  rules       = local.zone_custom_firewall_rules
}

import {
  to = cloudflare_ruleset.zone_custom_firewall
  id = "zones/${var.cloudflare_zone_id}/${var.zone_custom_firewall_ruleset_id}"
}
