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

resource "hcloud_server" "worker" {
  count = var.worker_count

  name        = "${var.cluster_name}-worker-${count.index + 1}"
  server_type = var.worker_server_type
  image       = var.talos_image_id
  location    = var.worker_location

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.this.id
  }

  firewall_ids = [hcloud_firewall.worker.id]

  labels = {
    cluster = var.cluster_name
    role    = "worker"
  }

  delete_protection  = false
  rebuild_protection = false

  depends_on = [hcloud_network_subnet.this]
}
