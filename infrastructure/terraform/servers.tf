resource "hcloud_server" "control_plane" {
  count = 3

  name = "${var.cluster_name}-cp-${count.index + 1}"
  server_type = (
    var.control_plane_server_types != null
    ? var.control_plane_server_types[count.index]
    : var.control_plane_server_type
  )
  image    = var.talos_image_id
  location = var.control_plane_locations[count.index]

  # Talos is API-only; no SSH access needed.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.this.id
    # Required with Terraform 1.4+ to avoid perpetual detach/reattach diffs.
    # https://github.com/hetznercloud/terraform-provider-hcloud/issues/650
    alias_ips = []
  }

  firewall_ids = [hcloud_firewall.control_plane.id]

  labels = {
    cluster = var.cluster_name
    role    = "control-plane"
  }

  # Prevent accidental deletion in production.
  delete_protection  = true
  rebuild_protection = true

  # cp-2 is currently in nbg1 (its Hetzner server predates the fsn1
  # consolidation). location is immutable on hcloud_server, so moving it
  # requires destroy + recreate, which delete_protection blocks. Ignore
  # location drift for now and migrate cp-2 to fsn1 manually later:
  #   1. Remove delete_protection (temporarily) and delete cp-2 in Hetzner.
  #   2. Remove cp-2 from Omni (omnictl delete clustermachine <id>).
  #   3. Remove this ignore_changes and apply — Terraform recreates cp-2
  #      in fsn1 and the Omni machine_set_node assigns it.
  lifecycle {
    ignore_changes = [location]
  }

  depends_on = [hcloud_network_subnet.this]
}

# Worker nodes are provisioned dynamically by the Hetzner Omni infra provider
# (see hetzner_infra_provider.tf) instead of a static hcloud_server fleet here.
