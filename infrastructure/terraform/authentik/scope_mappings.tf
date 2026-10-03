# Observability scopes. The gateway's AuthorizationPolicies (istio-ingress) match on
# these scope names; the mappings themselves only need to allow the scope.
locals {
  # Ordered list (provider property_mappings order matters for a clean plan).
  observability_scopes = [
    "mimir:read",
    "mimir:write",
    "loki:read",
    "loki:write",
    "tempo:read",
    "tempo:write",
  ]
}

resource "authentik_property_mapping_provider_scope" "observability" {
  for_each = toset(local.observability_scopes)

  name        = "Observability ${each.key}"
  description = "Observability scope ${each.key}"
  scope_name  = each.key
  expression  = "return True"
}

# tenant claim -> X-Scope-OrgID at the gateway. A service account's own
# observability_tenant wins; otherwise a human gets the pipe-joined tenant_id of every
# tenant group they belong to (query-only multi-tenancy); otherwise witl-xyz.
resource "authentik_property_mapping_provider_scope" "observability_tenant_id" {
  name        = "Observability tenant_id"
  description = "Named Mimir/Loki/Tempo tenant; default witl-xyz (witl-xyz / home-ops + cloud-ops)"
  scope_name  = "tenant"
  expression  = <<-EOT
    tenant_ids = [
        g.attributes.get("tenant_id")
        for g in request.user.ak_groups.all()
        if g.attributes.get("tenant_id")
    ]
    return {
        "tenant_id": (
            request.user.attributes.get("observability_tenant")
            or "|".join(sorted(set(tenant_ids)))
            or "witl-xyz"
        ),
    }
  EOT
}

resource "authentik_property_mapping_provider_scope" "oauth2_tenant_id_from_service_account_attribute" {
  name       = "OAuth2 tenant_id (from service account attribute)"
  scope_name = "tenant_id"
  expression = <<-EOT
    return {
      "tenant_id": request.user.attributes.get("tenant_id"),
    }
  EOT
}

resource "authentik_property_mapping_provider_scope" "oauth2_groups" {
  name       = "OAuth2 groups (ak_groups)"
  scope_name = "groups"
  expression = <<-EOT
    return {
      "groups": [g.name for g in request.user.ak_groups.all()],
    }
  EOT
}
