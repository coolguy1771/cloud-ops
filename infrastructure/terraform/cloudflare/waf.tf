# Bot Fight Mode cannot be skipped via WAF custom rules. An IP Access Rule
# Allow matching first is the supported exception path for Free/Pro BFM.
# https://developers.cloudflare.com/bots/get-started/bot-fight-mode/
#
# This is sufficient for in-cluster clients (Kiali) fetching Authentik OIDC
# metadata at https://auth.cloud.witl.xyz/.../.well-known/openid-configuration
resource "cloudflare_access_rule" "hetzner_asn_allow" {
  account_id = var.cloudflare_account_id
  mode       = "whitelist"
  notes      = "Hetzner Cloud ASN — allow cluster egress (Kiali/Authentik OIDC machine clients); bypasses Bot Fight Mode"
  configuration = {
    target = "asn"
    value  = var.hetzner_asn
  }
}

# Zone already has an entry-point ruleset for http_request_firewall_custom
# (Cloudflare allows only one). To add a path-based Skip rule later, import
# that ruleset and append to its `rules` instead of creating a new ruleset:
#
#   terraform import cloudflare_ruleset.zone_custom_firewall \
#     ${var.cloudflare_zone_id}/<ruleset_id>
#
# List: GET /zones/$ZONE_ID/rulesets?phase=http_request_firewall_custom
