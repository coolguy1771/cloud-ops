resource "hcloud_load_balancer" "control_plane" {
  name               = "${var.cluster_name}-control-plane"
  load_balancer_type = "lb11"
  network_zone       = var.network_zone

  labels = {
    cluster = var.cluster_name
    role    = "control-plane"
  }
}

# Attach LB to the private network so it can reach nodes via private IPs.
resource "hcloud_load_balancer_network" "control_plane" {
  load_balancer_id = hcloud_load_balancer.control_plane.id
  network_id       = hcloud_network.this.id

  depends_on = [hcloud_network_subnet.this]
}

resource "hcloud_load_balancer_service" "kube_api" {
  load_balancer_id = hcloud_load_balancer.control_plane.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

# Target all servers labelled role=control-plane via their private IPs.
resource "hcloud_load_balancer_target" "control_plane" {
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.control_plane.id
  label_selector   = "cluster=${var.cluster_name},role=control-plane"
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.control_plane]
}
