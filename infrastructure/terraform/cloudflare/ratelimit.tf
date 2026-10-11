# Zone http_ratelimit entry point. Pro allows two rules; trusted sources skip
# this phase from waf.tf.

resource "cloudflare_ruleset" "zone_ratelimit" {
  zone_id     = var.cloudflare_zone_id
  name        = "default"
  description = "Zone rate limiting rules (managed by Terraform)"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      # OIDC machine endpoints (/application/o/*) are excluded so token
      # refreshes from Grafana/Alloy never trip the limit.
      ref         = "5851ec34d3c8422c934150a40c15f00b"
      description = "Rate limit Authentik interactive auth (excl. OIDC machine endpoints)"
      enabled     = true
      action      = "managed_challenge"
      expression  = "http.host eq \"${var.authentik_host}\" and http.request.method eq \"POST\" and not starts_with(http.request.uri.path, \"/application/o/\")"
      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 60
        requests_per_period = 20
        mitigation_timeout  = 600
      }
    },
  ]
}

import {
  to = cloudflare_ruleset.zone_ratelimit
  id = "zones/${var.cloudflare_zone_id}/cd69dfe6428640988186fadd2dbbd8c5"
}
