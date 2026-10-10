locals {
  # Hosts that machine clients (Alloy, cloud-ops Grafana/OIDC clients) call directly.
  machine_client_hosts = [
    var.authentik_host,
    "loki.cloud.witl.xyz",
    "mimir.cloud.witl.xyz",
    "tempo.cloud.witl.xyz",
  ]

  # Phases skipped for trusted sources. witl.xyz is on Pro, so Super Bot Fight
  # Mode (http_request_sbfm) can be skipped here without an IP Access rule.
  trusted_skip_phases = [
    "http_ratelimit",
    "http_request_firewall_managed",
    "http_request_sbfm",
  ]

  # Order matters: a skip with ruleset = "current" ends evaluation of this
  # ruleset, so every source-based skip must come before the path-based
  # Authentik rule or it never runs for the token endpoints.
  # refs match the IDs of the rules that existed before Terraform managed them.
  zone_custom_firewall_rules = [
    {
      ref         = "fa03b3b7d13c43c89e9a543d962bfe7e"
      description = "Block: manual blocklist ($manual_blocklist)"
      enabled     = true
      action      = "block"
      expression  = "ip.src in $manual_blocklist"
    },
    {
      ref         = "b204f18bb67b433fb79b27c029777baf"
      description = "Challenge: leaked username+password detected"
      enabled     = true
      action      = "managed_challenge"
      expression  = "cf.waf.credential_check.username_and_password_leaked"
    },
    {
      ref         = "464ea2bf8bbb4283bea8def2a7fbee9c"
      description = "Skip: trusted operator IPs ($trusted_ips)"
      enabled     = true
      action      = "skip"
      expression  = "ip.src in $trusted_ips"
      action_parameters = {
        phases  = local.trusted_skip_phases
        ruleset = "current"
      }
      logging = { enabled = true }
    },
    {
      ref         = "e0ea66e29e1043f192660b97d5731c74"
      description = "Skip: machine clients ($telemetry_nodes, cloud-ops AS${var.hetzner_asn}) -> auth/loki/mimir/tempo"
      enabled     = true
      action      = "skip"
      expression  = "(ip.src in $telemetry_nodes or ip.src.asnum eq ${var.hetzner_asn}) and http.host in {${join(" ", [for h in local.machine_client_hosts : "\"${h}\""])}}"
      action_parameters = {
        phases  = local.trusted_skip_phases
        ruleset = "current"
      }
      logging = { enabled = true }
    },
    {
      # Everyone else still goes through managed WAF + rate limiting on these
      # paths; only bot fight mode and the geo challenge below are skipped.
      ref         = "4d2b736a6b2f4fe3b8731c1aa38a4a9f"
      description = "Skip: Authentik machine OIDC endpoints (token/userinfo/introspect/JWKS/discovery)"
      enabled     = true
      action      = "skip"
      expression  = <<-EOT
        (http.host eq "${var.authentik_host}" and (
          ends_with(http.request.uri.path, "/.well-known/openid-configuration") or
          starts_with(http.request.uri.path, "/application/o/token") or
          starts_with(http.request.uri.path, "/application/o/userinfo") or
          starts_with(http.request.uri.path, "/application/o/introspect") or
          http.request.uri.path contains "/jwks/"
        ))
      EOT
      action_parameters = {
        phases  = ["http_request_sbfm"]
        ruleset = "current"
      }
      logging = { enabled = true }
    },
    {
      ref         = "14fd2feeb17f4117bf6894b5694acce0"
      description = "Skip: GitHub (AS36459) -> flux webhooks"
      enabled     = true
      action      = "skip"
      expression  = "ip.src.asnum eq 36459 and http.host in {\"flux-webhook.witl.xyz\" \"flux-webhook.cloud.witl.xyz\"}"
      action_parameters = {
        ruleset = "current"
      }
      logging = { enabled = true }
    },
    {
      ref         = "25a8900753454f0eaa01e21ba5f0ec76"
      description = "Challenge: traffic outside CA/IE/GB/US/PT"
      enabled     = true
      action      = "managed_challenge"
      expression  = "not ip.src.country in {\"CA\" \"IE\" \"GB\" \"US\" \"PT\"}"
    },
  ]
}

resource "cloudflare_ruleset" "zone_custom_firewall" {
  zone_id     = var.cloudflare_zone_id
  name        = var.zone_custom_firewall_name
  description = "Zone custom security rules (managed by Terraform)"
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  rules       = local.zone_custom_firewall_rules

  # Rule expressions reference these lists by name.
  depends_on = [
    cloudflare_list.manual_blocklist,
    cloudflare_list.telemetry_nodes,
    cloudflare_list.trusted_ips,
  ]
}

import {
  to = cloudflare_ruleset.zone_custom_firewall
  id = "zones/${var.cloudflare_zone_id}/${var.zone_custom_firewall_ruleset_id}"
}
