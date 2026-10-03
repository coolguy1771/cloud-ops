variable "authentik_url" {
  description = "Authentik base URL."
  type        = string
  default     = "https://auth.cloud.witl.xyz"
}

variable "authentik_token" {
  description = "API token (intent: API) for the `terraform` service account."
  type        = string
  sensitive   = true
}

variable "turnstile_secret_key" {
  description = "Cloudflare Turnstile secret key for the login captcha stage."
  type        = string
  sensitive   = true
}
