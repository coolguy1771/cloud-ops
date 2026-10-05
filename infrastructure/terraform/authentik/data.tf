# Objects owned by authentik's shipped default blueprints. Referenced, not managed.

data "authentik_certificate_key_pair" "self_signed" {
  name = "authentik Self-signed Certificate"
  # Only the ID is needed; don't pull the private key into state.
  fetch_certificate = false
  fetch_key         = false
}

data "authentik_flow" "default_provider_authorization_explicit_consent" {
  slug = "default-provider-authorization-explicit-consent"
}

data "authentik_flow" "default_provider_authorization_implicit_consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-invalidation-flow"
}

data "authentik_flow" "default_provider_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_flow" "default_user_settings_flow" {
  slug = "default-user-settings-flow"
}

data "authentik_stage" "default_authenticator_totp_setup" {
  name = "default-authenticator-totp-setup"
}

data "authentik_stage" "default_authenticator_webauthn_setup" {
  name = "default-authenticator-webauthn-setup"
}

data "authentik_property_mapping_provider_scope" "oidc" {
  for_each = toset(["openid", "email", "profile"])
  managed  = "goauthentik.io/providers/oauth2/scope-${each.key}"
}

data "authentik_property_mapping_provider_scope" "offline_access" {
  managed = "goauthentik.io/providers/oauth2/scope-offline_access"
}

# Human accounts are created through enrollment/invitations, not Terraform; they're
# looked up here only so group membership can be declared.
data "authentik_user" "human" {
  for_each = toset(local.human_usernames)
  username = each.value
}
