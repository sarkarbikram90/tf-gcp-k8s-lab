resource "google_compute_instance" "node" {
  for_each = var.instances

  name         = "${var.name_prefix}-${each.key}"
  machine_type = each.value.machine_type
  zone         = each.value.zone

  tags = [
    "k8s-node",
    "k8s-${each.value.role}"
  ]

  boot_disk {
    auto_delete = true

    initialize_params {
      image = var.os_image
      size  = each.value.disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_id

    # Omit access_config to ensure zero public IP exposure when assign_public_ip is false
    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]
  }
}
