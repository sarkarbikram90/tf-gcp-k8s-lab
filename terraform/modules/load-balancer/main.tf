# ------------------------------------------------------------------------------
# 1. Group Control Plane VMs by Zone into Unmanaged Instance Groups
# ------------------------------------------------------------------------------
locals {
  cp_instances_by_zone = {
    for inst in var.control_plane_instances : inst.zone => inst.self_link...
  }
}

resource "google_compute_instance_group" "cp_group" {
  for_each  = local.cp_instances_by_zone
  name      = "${var.name}-cp-ig-${each.key}"
  zone      = each.key
  instances = each.value
}

# ------------------------------------------------------------------------------
# 2. Regional Health Check for Kubernetes API Server (:6443)
# ------------------------------------------------------------------------------
resource "google_compute_region_health_check" "k8s_api" {
  name               = "${var.name}-api-health-check"
  region             = var.region
  timeout_sec        = 5
  check_interval_sec = 10

  tcp_health_check {
    port = 6443
  }
}

# ------------------------------------------------------------------------------
# 3. Regional Backend Service (Internal TCP Load Balancer)
# ------------------------------------------------------------------------------
resource "google_compute_region_backend_service" "k8s_api" {
  name                  = "${var.name}-api-backend"
  region                = var.region
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.k8s_api.id]

  dynamic "backend" {
    for_each = google_compute_instance_group.cp_group
    content {
      group = backend.value.id
    }
  }
}

# ------------------------------------------------------------------------------
# 4. Internal Forwarding Rule (:6443 Control Plane VIP)
# ------------------------------------------------------------------------------
resource "google_compute_forwarding_rule" "k8s_api" {
  name                  = "${var.name}-api-forwarding-rule"
  region                = var.region
  network               = var.network_id
  subnetwork            = var.subnet_id
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.k8s_api.id
  ports                 = ["6443"]
  ip_address            = var.api_lb_ip
  ip_protocol           = "TCP"
}
