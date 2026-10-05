output "observability_m2m_client_id" {
  description = "client_id shared by every observability M2M tenant."
  value       = authentik_provider_oauth2.observability_m2m.client_id
}

output "m2m_client_secrets" {
  description = "client_secret per M2M service account created with create_token = true."
  sensitive   = true
  value = {
    for k, t in authentik_token.m2m : k => base64encode("${k}:${t.key}")
  }
}
