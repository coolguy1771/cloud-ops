# One-time adoption of objects that previously lived only in the authentik UI,
# shell scripts, or the security-hardening blueprint. Delete after the first apply.

import {
  to = authentik_provider_oauth2.hubble
  id = "39"
}

import {
  to = authentik_provider_oauth2.kiali
  id = "34"
}

import {
  to = authentik_provider_oauth2.hermes
  id = "2"
}

import {
  to = authentik_provider_oauth2.provider_for_kiali
  id = "37"
}

import {
  to = authentik_provider_oauth2.grafana_kiali_m2m
  id = "38"
}

import {
  to = authentik_provider_ldap.unifi
  id = "74"
}

import {
  to = authentik_provider_oauth2.level
  id = "41"
}

import {
  to = authentik_provider_oauth2.grafana
  id = "36"
}

import {
  to = authentik_provider_oauth2.observability_m2m
  id = "35"
}

import {
  to = authentik_application.hermes
  id = "hermes"
}

import {
  to = authentik_application.kiali
  id = "kiali"
}

import {
  to = authentik_application.observability_m2m
  id = "observability-m2m"
}

import {
  to = authentik_application.grafana
  id = "grafana"
}

import {
  to = authentik_application.grafana_kiali_m2m
  id = "grafana-kiali-m2m"
}

import {
  to = authentik_application.hubble
  id = "hubble"
}

import {
  to = authentik_application.level
  id = "level"
}

import {
  to = authentik_application.unifi
  id = "unifi"
}

import {
  to = authentik_outpost.ldap_home
  id = "213b3c1d-a03f-41df-ba33-53f8776ad154"
}

import {
  to = authentik_brand.default
  id = "a20671c5-4d7f-49bb-bb5d-803b11e0f252"
}

import {
  to = authentik_group.witl_authentik_admin
  id = "0bdd92b7-5a56-4ec2-9eb6-4eb519f19168"
}

import {
  to = authentik_group.access["witl-homeassistant-user"]
  id = "695bdb18-dab5-4246-b1cb-ea4f8c1a9013"
}

import {
  to = authentik_group.access["witl-cloud-ops-user"]
  id = "02a6972c-a2f5-44bb-aca0-d2ef9d77349b"
}

import {
  to = authentik_group.access["icb-workspace-admin"]
  id = "855438d2-8e4d-498c-b680-1792f7a8e0e4"
}

import {
  to = authentik_group.access["witl-jellyfin-user"]
  id = "735a2a39-92cc-4e70-a627-5d29940efc3c"
}

import {
  to = authentik_group.access["icb-grafana-user"]
  id = "5cd68ecb-98e3-46d3-837f-8e042b055a65"
}

import {
  to = authentik_group.access["witl-aws-user"]
  id = "963884d5-11c7-4a8b-807a-b3acfa65c863"
}

import {
  to = authentik_group.access["witl-aws-admin"]
  id = "cb4ffef1-c794-44a4-b15d-fb477ec3ea7a"
}

import {
  to = authentik_group.access["icb-workspace-user"]
  id = "82088f85-2884-4095-9aaf-72dc9a7d9084"
}

import {
  to = authentik_group.access["icb-grafana-admin"]
  id = "3da5eebd-ef05-4025-87e0-0341df2edc3e"
}

import {
  to = authentik_group.access["witl-jellyfin-admin"]
  id = "f9b8fcc1-9937-48d9-bcaf-449cf6e60488"
}

import {
  to = authentik_group.access["witl-grafana-user"]
  id = "e88187ad-4fe4-4c7c-8157-5e5ce67586e4"
}

import {
  to = authentik_group.access["witl-unifi-user"]
  id = "aa36b064-6888-4d43-8fd0-e3723ecb9d19"
}

import {
  to = authentik_group.access["Kiali Access"]
  id = "c9a9baa1-63f3-4f58-bdcb-c8bc3c534c72"
}

import {
  to = authentik_group.access["Grafana Access"]
  id = "1d4e3f94-b47c-4ce9-9398-a7958da25ef2"
}

import {
  to = authentik_group.access["Observability Superuser"]
  id = "78a597c5-25cf-452d-ae7b-5a9fe4b3df87"
}

import {
  to = authentik_group.access["cloud-ops-admin"]
  id = "8eb0f31d-4251-46be-bbce-26a7e9a5364f"
}

import {
  to = authentik_group.tenant["icbplays-net"]
  id = "d5c97af3-41e6-416a-9ee5-e570ff90fae1"
}

import {
  to = authentik_group.tenant["witl-xyz"]
  id = "8874ab02-bdba-4705-9b5e-211661d2f52f"
}

import {
  to = authentik_group.tenant["helo"]
  id = "160084fa-b934-4617-a63f-0b8a8b2cea99"
}

import {
  to = authentik_user.m2m["m2m-witl-xyz"]
  id = "22"
}

import {
  to = authentik_user.m2m["m2m-helo"]
  id = "57"
}

import {
  to = authentik_user.m2m["observability-icbplays-net"]
  id = "19"
}

import {
  to = authentik_user.ldap_bind
  id = "56"
}

import {
  to = authentik_user.m2m["m2m-icbplays-net"]
  id = "23"
}

import {
  to = authentik_property_mapping_provider_scope.observability["mimir:read"]
  id = "b841f75a-31a5-49a2-9295-d180a1d24005"
}

import {
  to = authentik_property_mapping_provider_scope.observability["mimir:write"]
  id = "aa73e610-2fbf-4d27-b89c-3fc1e6cc1953"
}

import {
  to = authentik_property_mapping_provider_scope.observability["loki:read"]
  id = "ab52dfe0-23aa-4b09-a257-2c8890fb7403"
}

import {
  to = authentik_property_mapping_provider_scope.observability["loki:write"]
  id = "6a49531e-449a-49f1-9754-cf4a8c4aa983"
}

import {
  to = authentik_property_mapping_provider_scope.observability["tempo:read"]
  id = "f92f93a9-9610-42ce-b394-e8a806c9b202"
}

import {
  to = authentik_property_mapping_provider_scope.observability["tempo:write"]
  id = "8566d187-988a-43d2-b457-9b2e7c1de8eb"
}

import {
  to = authentik_property_mapping_provider_scope.observability_tenant_id
  id = "fc3492ae-f63a-41fc-9a1d-8905d31d48cf"
}

import {
  to = authentik_property_mapping_provider_scope.oauth2_groups
  id = "5b0cedc0-1986-4244-828b-4c1985b26328"
}

import {
  to = authentik_property_mapping_provider_scope.oauth2_tenant_id_from_service_account_attribute
  id = "abd1ca50-44b7-4d5f-80c0-a9c72f8389af"
}

import {
  to = authentik_stage_captcha.turnstile_login
  id = "6fcab7ad-374f-4474-9c23-ba47f821ee7f"
}

import {
  to = authentik_stage_password.ldap_authentication_password
  id = "cc59b0a5-6fec-4712-bee1-47dd39b2a5f9"
}

import {
  to = authentik_stage_authenticator_validate.default_authentication_mfa_validation
  id = "3f7b00f4-f945-45a7-bd5b-e4f74647dee9"
}

import {
  to = authentik_stage_identification.default_authentication_identification
  id = "67c98a3f-ff43-4b98-a4be-0f8e5cffd2ad"
}

import {
  to = authentik_stage_user_login.default_authentication_login
  id = "d4ef70a2-9d3b-4dfe-b0f0-51439c3a69ae"
}

import {
  to = authentik_stage_identification.ldap_authentication_identification
  id = "8d94baa1-576b-4855-91cf-510dda8b7374"
}

import {
  to = authentik_flow.default_authentication_flow
  id = "default-authentication-flow"
}

import {
  to = authentik_flow.ldap_authentication
  id = "ldap-authentication"
}

import {
  to = authentik_flow_stage_binding.ldap_authentication_identification
  id = "76432181-41f1-49d3-a888-269fb1bb2a7f"
}

import {
  to = authentik_flow_stage_binding.ldap_authentication_login
  id = "f20ac9e6-08b7-4038-8ffa-2d1129e8bca1"
}

import {
  to = authentik_flow_stage_binding.default_authentication_turnstile
  id = "e53baa8b-0191-4b3c-8d01-41690c5396a0"
}

import {
  to = authentik_policy_password.default_password_change_password_policy
  id = "fca48693-709f-4674-a979-02f51cc47d8d"
}

import {
  to = authentik_policy_expression.hubble_cloud_ops_admin
  id = "6b5b924d-c221-417d-9179-9bb4776f1fd4"
}

import {
  to = authentik_policy_binding.kiali_access
  id = "601ea572-6a77-4dc4-bf42-ed8a917c2551"
}

import {
  to = authentik_policy_binding.unifi_witl_unifi_user
  id = "1bf2535d-c8d6-4e9a-b50d-e345b11c8237"
}

import {
  to = authentik_policy_binding.unifi_ldap_bind
  id = "c1385ec9-d40e-44f8-9e63-61aac3c5fb6f"
}

import {
  to = authentik_rbac_role.unifi_ldap_search
  id = "fe74778a-9ccd-46dc-b765-64f78aba9a23"
}
