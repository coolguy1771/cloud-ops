resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_launch_url   = "https://grafana.cloud.witl.xyz"
}

resource "authentik_application" "kiali" {
  name              = "Kiali"
  slug              = "kiali"
  protocol_provider = authentik_provider_oauth2.kiali.id
  meta_launch_url   = "https://kiali.cloud.witl.xyz/"
}

resource "authentik_application" "grafana_kiali_m2m" {
  name              = "Grafana Kiali M2M"
  slug              = "grafana-kiali-m2m"
  protocol_provider = authentik_provider_oauth2.grafana_kiali_m2m.id
}

resource "authentik_application" "observability_m2m" {
  name              = "Observability M2M"
  slug              = "observability-m2m"
  protocol_provider = authentik_provider_oauth2.observability_m2m.id
}

resource "authentik_application" "hubble" {
  name              = "Hubble"
  slug              = "hubble"
  protocol_provider = authentik_provider_oauth2.hubble.id
  meta_launch_url   = "https://hubble.cloud.witl.xyz"
}

resource "authentik_application" "hermes" {
  name              = "Hermes"
  slug              = "hermes"
  protocol_provider = authentik_provider_oauth2.hermes.id
  meta_launch_url   = "https://hermes.286k.co"
  open_in_new_tab   = true
}

resource "authentik_application" "level" {
  name              = "Level"
  slug              = "level"
  protocol_provider = authentik_provider_oauth2.level.id
}

resource "authentik_application" "unifi" {
  name              = "Unifi"
  slug              = "unifi"
  protocol_provider = authentik_provider_ldap.unifi.id
}

resource "authentik_outpost" "ldap_home" {
  name               = "ldap-home"
  type               = "ldap"
  protocol_providers = [authentik_provider_ldap.unifi.id]
  # No service connection: the outpost container is deployed by hand at home.
  config = jsonencode({
    authentik_host                   = "https://auth.cloud.witl.xyz/"
    authentik_host_browser           = ""
    authentik_host_insecure          = false
    container_image                  = null
    docker_labels                    = null
    docker_map_ports                 = true
    docker_network                   = null
    kubernetes_disable_x509_strict   = false
    kubernetes_disabled_components   = []
    kubernetes_httproute_annotations = {}
    kubernetes_httproute_parent_refs = []
    kubernetes_image_pull_secrets    = []
    kubernetes_ingress_annotations   = {}
    kubernetes_ingress_class_name    = null
    kubernetes_ingress_path_type     = null
    kubernetes_ingress_secret_name   = "authentik-outpost-tls"
    kubernetes_json_patches          = null
    kubernetes_namespace             = "authentik"
    kubernetes_replicas              = 1
    kubernetes_service_type          = "ClusterIP"
    log_level                        = "info"
    object_naming_template           = "ak-outpost-%(name)s"
    refresh_interval                 = "minutes=5"
  })
}

resource "authentik_brand" "default" {
  domain              = "authentik-default"
  default             = true
  branding_title      = "authentik"
  branding_logo       = "/static/dist/assets/icons/icon_left_brand.svg"
  branding_favicon    = "/static/dist/assets/icons/icon.png"
  flow_authentication = authentik_flow.default_authentication_flow.uuid
  flow_invalidation   = data.authentik_flow.default_invalidation_flow.id
  flow_user_settings  = data.authentik_flow.default_user_settings_flow.id
}
