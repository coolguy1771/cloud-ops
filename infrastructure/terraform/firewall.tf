resource "hcloud_firewall" "control_plane" {
  name = "${var.cluster_name}-control-plane"

  labels = {
    cluster = var.cluster_name
    role    = "control-plane"
  }

  # Kubernetes API — kubectl + LB health check
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Talos API — omnictl / talosctl
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50000"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # etcd — peer and client traffic, cluster-internal only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "2379-2380"
    source_ips = [var.network_ip_range]
  }

  # Kubelet — cluster-internal only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [var.network_ip_range]
  }

  # Cilium health + Hubble — cluster-internal only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "4240"
    source_ips = [var.network_ip_range]
  }

  # ICMP — load balancer health checks + diagnostics
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall" "worker" {
  name = "${var.cluster_name}-worker"

  labels = {
    cluster = var.cluster_name
    role    = "worker"
  }

  # Talos API — omnictl / talosctl
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "50000"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Kubelet — cluster-internal only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [var.network_ip_range]
  }

  # NodePort range — restrict further if you use an ingress LB instead
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "30000-32767"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Cilium health — cluster-internal only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "4240"
    source_ips = [var.network_ip_range]
  }

  # ICMP
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}
