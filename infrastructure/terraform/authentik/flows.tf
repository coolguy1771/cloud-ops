# Login flow hardening (replaces the security-hardening blueprint, which never applied:
# blueprints are atomic and its identification-stage entry failed validation).
#
# These are objects created by authentik's shipped default blueprints. Terraform owns
# the fields set here; the shipped blueprints don't set them (checked against
# 2026.8.x), except default-password-change-password-policy, whose length_min / HIBP /
# error_message the shipped flow-password-change.yaml also sets. Re-check after
# authentik upgrades: a re-applied default blueprint would show up as drift in plan.

resource "authentik_flow" "default_authentication_flow" {
  name               = "Welcome to authentik!"
  title              = "Welcome to authentik!"
  slug               = "default-authentication-flow"
  designation        = "authentication"
  compatibility_mode = false
  background         = "/static/dist/assets/images/flow_background.jpg"
}

# Don't reveal whether an identifier matched an account (name/avatar).
resource "authentik_stage_identification" "default_authentication_identification" {
  name                      = "default-authentication-identification"
  user_fields               = ["email", "username"]
  case_insensitive_matching = true
  pretend_user_exists       = true
  show_matched_user         = false
}

resource "authentik_stage_captcha" "turnstile_login" {
  name        = "turnstile-login"
  js_url      = "https://challenges.cloudflare.com/turnstile/v0/api.js"
  api_url     = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
  public_key  = "0x4AAAAAAEptAcIx8ho82YFk"
  private_key = var.turnstile_secret_key
  interactive = true
}

resource "authentik_flow_stage_binding" "default_authentication_turnstile" {
  target = authentik_flow.default_authentication_flow.uuid
  stage  = authentik_stage_captcha.turnstile_login.id
  order  = 15
}

# Force MFA enrollment (WebAuthn preferred, TOTP fallback, static recovery codes)
# instead of letting users with no device skip it.
resource "authentik_stage_authenticator_validate" "default_authentication_mfa_validation" {
  name                       = "default-authentication-mfa-validation"
  device_classes             = ["static", "totp", "webauthn"]
  not_configured_action      = "configure"
  webauthn_user_verification = "required"
  last_auth_threshold        = "seconds=0"
  configuration_stages = [
    data.authentik_stage.default_authenticator_webauthn_setup.id,
    data.authentik_stage.default_authenticator_totp_setup.id,
  ]
}

# network_binding/geoip_binding are inert until GeoIP databases are mounted
# (geoip.enabled in the authentik HelmRelease).
resource "authentik_stage_user_login" "default_authentication_login" {
  name                     = "default-authentication-login"
  terminate_other_sessions = true
  remember_device          = "seconds=0"
  network_binding          = "bind_asn"
  geoip_binding            = "bind_continent"
}

resource "authentik_policy_password" "default_password_change_password_policy" {
  name                    = "default-password-change-password-policy"
  length_min              = 15
  check_static_rules      = true
  check_zxcvbn            = true
  zxcvbn_score_threshold  = 2
  check_have_i_been_pwned = true
  hibp_allowed_count      = 0
  symbol_charset          = "!\\\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ "
  error_message           = "Password must be at least 15 characters and must not have appeared in a known data breach."
}

# ---------------------------------------------------------------------------------
# LDAP bind flow for the UniFi outpost: no captcha or WebAuthn (the outpost can't
# answer those challenges), and only reachable from an outpost.

resource "authentik_flow" "ldap_authentication" {
  name               = "LDAP Authentication"
  title              = "LDAP Authentication"
  slug               = "ldap-authentication"
  designation        = "authentication"
  authentication     = "require_outpost"
  compatibility_mode = false
  background         = "/static/dist/assets/images/flow_background.jpg"
}

resource "authentik_stage_password" "ldap_authentication_password" {
  name     = "ldap-authentication-password"
  backends = ["authentik.core.auth.InbuiltBackend", "authentik.core.auth.TokenBackend"]
}

resource "authentik_stage_identification" "ldap_authentication_identification" {
  name                      = "ldap-authentication-identification"
  user_fields               = ["username", "email"]
  password_stage            = authentik_stage_password.ldap_authentication_password.id
  case_insensitive_matching = true
  pretend_user_exists       = false
  show_matched_user         = false
}

resource "authentik_flow_stage_binding" "ldap_authentication_identification" {
  target = authentik_flow.ldap_authentication.uuid
  stage  = authentik_stage_identification.ldap_authentication_identification.id
  order  = 10
}

# Own login stage (was default-authentication-login): the hardened one terminates
# other sessions, so every UniFi LDAP bind would log the user out of the web UI.
resource "authentik_stage_user_login" "ldap_authentication_login" {
  name = "ldap-authentication-login"
}

resource "authentik_flow_stage_binding" "ldap_authentication_login" {
  target = authentik_flow.ldap_authentication.uuid
  stage  = authentik_stage_user_login.ldap_authentication_login.id
  order  = 30
}
