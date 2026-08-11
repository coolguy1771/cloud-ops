output "control_plane_ips" {
  description = "Public IPv4 addresses of control plane nodes"
  value       = hcloud_server.control_plane[*].ipv4_address
}

output "worker_ips" {
  description = "Public IPv4 addresses of worker nodes"
  value       = hcloud_server.worker[*].ipv4_address
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
