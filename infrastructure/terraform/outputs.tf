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
  value = merge(
    { for location, ms in omni_machine_set.workers : location => ms.name },
    local.hetzner_worker_machine_set_names
  )
}

output "hetzner_worker_machine_classes" {
  description = "MachineClass names used for dynamic Hetzner worker auto-provisioning, by location"
  value       = local.hetzner_worker_machine_class_names
}
