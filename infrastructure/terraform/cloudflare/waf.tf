locals {
  # Machine-only API hosts. Every request is authenticated at the origin (JWT at
  # the Istio gateway for loki/mimir/tempo, HMAC-signed receiver URLs for Flux
  # webhooks), and every legitimate client is automated, so bot scoring and the
  # geo challenge add friction without protection. Managed WAF still applies.
  api_hosts = [
    "loki.cloud.witl.xyz",
    "mimir.cloud.witl.xyz",
    "tempo.cloud.witl.xyz",
    "flux-webhook.cloud.witl.xyz",
    "flux-webhook.witl.xyz",
  ]

  # Phases skipped for trusted operator IPs. witl.xyz is on Pro, so Super Bot
  # Fight Mode (http_request_sbfm) can be skipped here without an IP Access rule.
  # Managed WAF (http_request_firewall_managed) is deliberately not skipped:
  # trusted sources still get CVE/OWASP inspection. Tune false positives with
  # targeted exceptions in managed.tf instead.
  trusted_skip_phases = [
    "http_ratelimit",
    "http_request_sbfm",
  ]

  # Bot fight mode and the geo challenge apply to interactive hosts only
  # (Authentik login, Grafana, Kiali, Hubble, public witl.xyz sites); API hosts
  # and Authentik's machine OIDC endpoints are exempted by host/path, not by
  # source IP or ASN, so new clients need no rule changes.
  #
  # Order matters: a skip with ruleset = "current" ends evaluation of this
  # ruleset (including the geo challenge at the end).
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
      description = "Skip: authenticated API hosts (loki/mimir/tempo/flux-webhook) -> bot fight mode, geo"
      enabled     = true
      action      = "skip"
      expression  = "http.host in {${join(" ", [for h in local.api_hosts : "\"${h}\""])}}"
      action_parameters = {
        phases  = ["http_request_sbfm"]
        ruleset = "current"
      }
      logging = { enabled = true }
    },
    {
      # Grafana/istiod/authservice in the cluster and external Alloy agents call
      # these. Login and admin paths stay behind bot fight mode, the geo
      # challenge and the interactive-auth rate limit.
      ref         = "4d2b736a6b2f4fe3b8731c1aa38a4a9f"
      description = "Skip: Authentik machine OIDC endpoints (token/userinfo/introspect/JWKS/discovery) -> bot fight mode, geo"
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
      ref         = "25a8900753454f0eaa01e21ba5f0ec76"
      description = "Challenge: interactive traffic outside CA/IE/GB/US/PT"
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
    cloudflare_list.trusted_ips,
  ]
}

import {
  to = cloudflare_ruleset.zone_custom_firewall
  id = "zones/${var.cloudflare_zone_id}/${var.zone_custom_firewall_ruleset_id}"
}
