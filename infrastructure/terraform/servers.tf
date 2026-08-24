resource "hcloud_server" "control_plane" {
  count = 3

  name        = "${var.cluster_name}-cp-${count.index + 1}"
  server_type = var.control_plane_server_type
  image       = var.talos_image_id
  location    = var.control_plane_locations[count.index]

  # Talos is API-only; no SSH access needed.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.this.id
  }

  firewall_ids = [hcloud_firewall.control_plane.id]

  labels = {
    cluster = var.cluster_name
    role    = "control-plane"
  }

  # Prevent accidental deletion in production.
  delete_protection  = false
  rebuild_protection = false

  depends_on = [hcloud_network_subnet.this]
}

# Worker nodes are provisioned dynamically by the Hetzner Omni infra provider
# (see hetzner_infra_provider.tf) instead of a static hcloud_server fleet here.
