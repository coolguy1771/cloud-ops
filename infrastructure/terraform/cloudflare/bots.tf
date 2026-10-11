# Super Bot Fight Mode (Pro) and zone security level. Machine clients that SBFM
# would challenge are exempted by skip rules in waf.tf (phase http_request_sbfm),
# not by IP Access allow rules: an IP Access allow bypasses every WAF phase on
# every host in the zone.

resource "cloudflare_bot_management" "zone" {
  zone_id = var.cloudflare_zone_id

  enable_js                       = true
  sbfm_definitely_automated       = "managed_challenge"
  sbfm_verified_bots              = "allow"
  sbfm_static_resource_protection = false
  optimize_wordpress              = false
  suppress_session_score          = false
  ai_bots_protection              = "block"
  crawler_protection              = "enabled"
  is_robots_txt_managed           = true
}

import {
  to = cloudflare_bot_management.zone
  id = var.cloudflare_zone_id
}

resource "cloudflare_zone_setting" "security_level" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "security_level"
  value      = "medium"
}

import {
  to = cloudflare_zone_setting.security_level
  id = "${var.cloudflare_zone_id}/security_level"
}
