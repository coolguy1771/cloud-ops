output "control_plane_ips" {
  description = "Public IPv4 addresses of control plane nodes"
  value       = hcloud_server.control_plane[*].ipv4_address
}

output "kubernetes_endpoint" {
  description = "Kubernetes API endpoint — use this as the cluster endpoint in Omni"
  value       = "https://${hcloud_load_balancer.control_plane.ipv4}:6443"
}

output "load_balancer_ipv4" {
  description = "Public IPv4 of the Kubernetes API load balancer"
  value       = hcloud_load_balancer.control_plane.ipv4
}

output "network_id" {
  description = "Hetzner private network ID — set as HCLOUD_NETWORK in 1Password for hcloud-ccm"
  value       = hcloud_network.this.id
}

output "network_name" {
  description = "Hetzner private network name"
  value       = hcloud_network.this.name
}

output "omni_cluster_name" {
  description = "Omni-managed cluster name"
  value       = omni_cluster.this.name
}

output "omni_control_plane_machine_set" {
  description = "Omni control plane machine set ID"
  value       = omni_machine_set.control_plane.name
}

output "omni_worker_machine_sets" {
  description = "Omni worker machine set IDs by Hetzner location (dynamic, allocated from per-location MachineClasses)"
  value       = { for location, ms in omni_machine_set.workers : location => ms.name }
}

output "hetzner_worker_machine_class" {
  description = "MachineClass name used for dynamic Hetzner worker auto-provisioning (single region, fsn1)"
  value       = omni_machine_class.hetzner_workers_fsn1.name
}

output "hetzner_infra_provider_key" {
  description = "Service-account key for the Hetzner infra-provider daemon (OMNI_SERVICE_ACCOUNT_KEY). Null after import — Omni does not return the private half; the daemon keeps its existing key. A fresh value appears only on create/renew."
  value       = omni_infra_provider.hetzner.key
  sensitive   = true
}
