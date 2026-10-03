# Groups, observability tenants, M2M service accounts, and application access policy.
#
# Replaces kubernetes/apps/authservice/scripts/setup-authentik-tenant-{claim,groups}.sh:
#   - new human tenant  -> add an entry to local.observability_tenants
#   - new M2M tenant    -> add an entry to local.m2m_service_accounts with
#                          create_token = true, apply, then read the client secret with
#                          `terraform output -json m2m_client_secrets`
# M2M clients authenticate to the Observability M2M provider with
#   client_id     = authentik_provider_oauth2.observability_m2m.client_id
#   client_secret = base64("<service-account-username>:<app-password-token>")
# authentik resolves the service account (and its observability_tenant) from the secret.

locals {
  human_usernames = ["akadmin", "twitlin", "dmanners", "lwitlin", "rwitlin", "mwitlin", "mwitlin2"]
  uid             = { for u, d in data.authentik_user.human : u => d.pk }

  # tenant_id -> members. Members get tenant_id aggregated into their `tenant` claim.
  observability_tenants = {
    "witl-xyz"     = ["twitlin", "akadmin"]
    "icbplays-net" = ["twitlin", "akadmin"]
    "helo"         = ["dmanners", "twitlin"]
  }

  m2m_service_accounts = {
    "m2m-witl-xyz"     = { tenant = "witl-xyz" }
    "m2m-icbplays-net" = { tenant = "icbplays-net" }
    "m2m-helo" = {
      tenant           = "helo"
      extra_attributes = { "goauthentik.io/user/token-expires" = false }
    }
    "observability-icbplays-net" = {
      tenant       = "icbplays-net"
      display_name = "Observability tenant icbplays-net"
      path         = "users"
    }
  }
}

resource "authentik_group" "tenant" {
  for_each = local.observability_tenants

  name       = "tenant-${each.key}"
  attributes = jsonencode({ tenant_id = each.key })
  users      = [for u in each.value : local.uid[u]]
}

resource "authentik_user" "m2m" {
  for_each = local.m2m_service_accounts

  username = each.key
  name     = try(each.value.display_name, each.key)
  type     = "service_account"
  path     = try(each.value.path, "goauthentik.io/service-accounts")
  attributes = jsonencode(merge(
    try(each.value.extra_attributes, {}),
    { observability_tenant = each.value.tenant },
  ))
}

resource "authentik_token" "m2m" {
  for_each = { for k, v in local.m2m_service_accounts : k => v if try(v.create_token, false) }

  identifier   = "${each.key}-app-password"
  user         = authentik_user.m2m[each.key].id
  intent       = "app_password"
  expiring     = false
  retrieve_key = true
  description  = "Observability M2M client secret for tenant ${each.value.tenant}"
}

# ---------------------------------------------------------------------------------
# Plain access groups

locals {
  access_groups = {
    "witl-homeassistant-user" = []
    "witl-cloud-ops-user"     = []
    "witl-jellyfin-user"      = []
    "witl-jellyfin-admin"     = []
    "witl-grafana-user"       = []
    "witl-aws-user"           = []
    "witl-aws-admin"          = []
    "icb-workspace-user"      = []
    "icb-workspace-admin"     = []
    "icb-grafana-user"        = []
    "icb-grafana-admin"       = []
    "witl-unifi-user"         = ["lwitlin", "rwitlin", "mwitlin2", "mwitlin", "twitlin"]
    "Kiali Access"            = ["twitlin", "akadmin"]
    "Grafana Access"          = ["twitlin", "akadmin"]
    "Observability Superuser" = ["twitlin", "akadmin"]
    "cloud-ops-admin"         = ["twitlin", "akadmin"]
  }
}

resource "authentik_group" "access" {
  for_each = local.access_groups

  name  = each.key
  users = [for u in each.value : local.uid[u]]
}

resource "authentik_group" "witl_authentik_admin" {
  name         = "witl-authentik-admin"
  is_superuser = true
  users        = [local.uid["twitlin"]]
}

# ---------------------------------------------------------------------------------
# Application access

resource "authentik_policy_binding" "kiali_access" {
  target = authentik_application.kiali.uuid
  group  = authentik_group.access["Kiali Access"].id
  order  = 0
}

resource "authentik_policy_expression" "hubble_cloud_ops_admin" {
  name       = "hubble-cloud-ops-admin"
  expression = "return ak_is_group_member(request.user, name=\"cloud-ops-admin\")"
}

# The gateway relies on authentik to gate Hubble (authservice CUSTOM policy); this
# binding was missing, which let any authentik user into the Hubble UI.
resource "authentik_policy_binding" "hubble_cloud_ops_admin" {
  target = authentik_application.hubble.uuid
  policy = authentik_policy_expression.hubble_cloud_ops_admin.id
  order  = 0
}

# UniFi: only witl-unifi-user members, plus the LDAP bind account.
resource "authentik_policy_binding" "unifi_witl_unifi_user" {
  target = authentik_application.unifi.uuid
  group  = authentik_group.access["witl-unifi-user"].id
  order  = 0
}

resource "authentik_policy_binding" "unifi_ldap_bind" {
  target = authentik_application.unifi.uuid
  user   = tonumber(authentik_user.ldap_bind.id)
  order  = 0
}

resource "authentik_user" "ldap_bind" {
  username   = "ldap-bind"
  name       = "ldap-bind"
  type       = "service_account"
  path       = "goauthentik.io/service-accounts"
  attributes = jsonencode({ "goauthentik.io/user/token-expires" = false })
  roles      = [authentik_rbac_role.unifi_ldap_search.id]
}

# Without search_full_directory the bind account can't search, and UniFi sync is empty.
resource "authentik_rbac_role" "unifi_ldap_search" {
  name = "unifi-ldap-search"
}

resource "authentik_rbac_permission_role" "unifi_ldap_search" {
  role       = authentik_rbac_role.unifi_ldap_search.id
  model      = "authentik_providers_ldap.ldapprovider"
  permission = "search_full_directory"
  object_id  = authentik_provider_ldap.unifi.id
}
