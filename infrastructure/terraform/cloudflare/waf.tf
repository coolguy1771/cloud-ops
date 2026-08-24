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

# Skip remaining WAF / Super Bot Fight Mode / rate-limit phases for Authentik
# OIDC endpoints. Complements the ASN allow (BFM) and covers managed rules.
#
# If this zone already has custom firewall rules managed outside Terraform,
# import the existing entry-point ruleset before apply:
#   terraform import cloudflare_ruleset.authentik_oidc_skip ZONE_ID/RULESET_ID
# then merge those rules into `rules` below so they are not dropped.
resource "cloudflare_ruleset" "authentik_oidc_skip" {
  zone_id     = var.cloudflare_zone_id
  name        = "Authentik OIDC machine clients"
  description = "Skip security phases for Authentik OIDC discovery/token/jwks used by in-cluster clients"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
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
    },
  ]
}
