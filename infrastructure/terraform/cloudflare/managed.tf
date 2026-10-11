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

  # Exceptions (skip) come first: a skip only bypasses execute rules listed
  # after it. Keep them scoped to host + path, and prefer skipping a single rule
  # ID over a whole ruleset when Security Events names the rule.
  # refs of the execute rules match the IDs that existed before Terraform.
  rules = [
    {
      # snappy/protobuf/OTLP bodies the WAF cannot parse meaningfully. The CVE
      # ruleset still runs and the gateway still requires a JWT.
      ref         = "exception_owasp_lgtm_ingest"
      description = "Exception: OWASP on LGTM ingest paths"
      enabled     = true
      action      = "skip"
      expression  = <<-EOT
        http.request.method eq "POST" and (
          (http.host eq "loki.cloud.witl.xyz" and http.request.uri.path eq "/loki/api/v1/push") or
          (http.host eq "mimir.cloud.witl.xyz" and http.request.uri.path in {"/api/v1/push" "/otlp/v1/metrics"}) or
          (http.host eq "tempo.cloud.witl.xyz" and starts_with(http.request.uri.path, "/v1/traces"))
        )
      EOT
      action_parameters = {
        rulesets = [local.cloudflare_owasp_ruleset_id]
      }
      logging = { enabled = true }
    },
    {
      # PromQL/LogQL/TraceQL ({...}, |~, regexes) read as injection to OWASP.
      ref         = "exception_owasp_grafana_query"
      description = "Exception: OWASP on Grafana query APIs"
      enabled     = true
      action      = "skip"
      expression  = <<-EOT
        http.host eq "grafana.cloud.witl.xyz" and (
          http.request.uri.path eq "/api/ds/query" or
          starts_with(http.request.uri.path, "/api/prometheus/") or
          starts_with(http.request.uri.path, "/api/datasources/proxy/")
        )
      EOT
      action_parameters = {
        rulesets = [local.cloudflare_owasp_ruleset_id]
      }
      logging = { enabled = true }
    },
    {
      # Ruler/Alertmanager config clients (mimirtool, Alloy mimir.rules) send
      # YAML without Content-Type.
      ref         = "exception_mimir_config_content_type"
      description = "Exception: Content-Type missing rule on Mimir ruler/alertmanager config API"
      enabled     = true
      action      = "skip"
      expression  = "http.host eq \"mimir.cloud.witl.xyz\" and (starts_with(http.request.uri.path, \"/prometheus/config/v1/rules\") or http.request.uri.path eq \"/api/v1/alerts\")"
      action_parameters = {
        rules = {
          (local.cloudflare_managed_ruleset_id) = ["3c51b23dc24f439d904e0f1054622f7d"] # Anomaly:Header:Content-Type - Missing
        }
      }
      logging = { enabled = true }
    },
    {
      # Token calls from Authentik clients tripped this (normally disabled) rule.
      ref         = "exception_authentik_token_drupal_xff"
      description = "Exception: Drupal XFF rule on Authentik OIDC token endpoint"
      enabled     = true
      action      = "skip"
      expression  = "http.host eq \"${var.authentik_host}\" and starts_with(http.request.uri.path, \"/application/o/token\")"
      action_parameters = {
        rules = {
          (local.cloudflare_managed_ruleset_id) = ["d6f6d394cb01400284cfb7971e7aed1e"] # Drupal - Anomaly:Header:X-Forwarded-For - CVE:CVE-2018-14774
        }
      }
      logging = { enabled = true }
    },
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
