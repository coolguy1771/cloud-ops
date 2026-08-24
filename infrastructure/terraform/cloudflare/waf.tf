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

  zone_custom_firewall_rules = concat(
    [local.authentik_oidc_skip_rule],
    var.zone_custom_firewall_extra_rules,
  )
}

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
