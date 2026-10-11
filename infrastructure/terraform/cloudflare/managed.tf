# Zone http_request_firewall_managed entry point: which managed rulesets run and
# how they are tuned. Skip rules in waf.tf (custom phase) can bypass this phase.
#
# The Cloudflare Managed Ruleset runs with Cloudflare's default rule selection.
# Do not set a ruleset-wide `enabled = true` override: it also turns on the
# rules Cloudflare ships disabled for false positives (Accept-header anomaly,
# Drupal XFF, large body, template injection, ...), which blocked Alloy pushes,
# Authentik token calls and Grafana queries. Turn on individual rules or tags
# instead, and add exceptions as `skip` rules placed before the execute rules.

locals {
  cloudflare_managed_ruleset_id      = "efb7b8c949ac4650a09736fc376e9aee"
  cloudflare_owasp_ruleset_id        = "4814384a9e5d4991b9815dcfc25d2f1f"
  cloudflare_leaked_creds_ruleset_id = "c2e184081120413c86c3ab7e14069605"
  owasp_anomaly_score_rule_id        = "6179ae15870a4bb7b2d480d4843b323c" # 949110: Inbound Anomaly Score Exceeded
  owasp_anomaly_score_threshold      = 60                                 # 60 = low sensitivity, 40 = medium, 25 = high
}

resource "cloudflare_ruleset" "zone_managed_waf" {
  zone_id     = var.cloudflare_zone_id
  name        = "default"
  description = "Zone managed WAF rulesets (managed by Terraform)"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  # refs match the IDs of the rules that existed before Terraform managed them.
  rules = [
    {
      ref         = "e0c9c66c1200436eab807536e70a448b"
      description = "Cloudflare Managed Ruleset (default rules)"
      enabled     = true
      action      = "execute"
      expression  = "true"
      action_parameters = {
        id      = local.cloudflare_managed_ruleset_id
        version = "latest"
      }
    },
    {
      ref         = "85600babe1064097ae335bcefa622716"
      description = "OWASP Core Ruleset (PL1-2, low sensitivity)"
      enabled     = true
      action      = "execute"
      expression  = "true"
      action_parameters = {
        id      = local.cloudflare_owasp_ruleset_id
        version = "latest"
        overrides = {
          enabled = true
          categories = [
            { category = "paranoia-level-3", enabled = false },
            { category = "paranoia-level-4", enabled = false },
          ]
          rules = [
            {
              id              = local.owasp_anomaly_score_rule_id
              action          = "block"
              enabled         = true
              score_threshold = local.owasp_anomaly_score_threshold
            },
          ]
        }
      }
    },
    {
      ref         = "ea8a141b6f0843dba1ce213ebe4a8b74"
      description = "Cloudflare Leaked credentials Check"
      enabled     = true
      action      = "execute"
      expression  = "true"
      action_parameters = {
        id      = local.cloudflare_leaked_creds_ruleset_id
        version = "latest"
      }
    },
  ]
}

import {
  to = cloudflare_ruleset.zone_managed_waf
  id = "zones/${var.cloudflare_zone_id}/7db1cd2ff4bb492bb746041a57dc118e"
}
