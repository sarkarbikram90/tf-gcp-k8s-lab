# ------------------------------------------------------------------------------
# 1. Internal Subnet Traffic (Pod overlay, CNI, etcd, Kubelet, DNS)
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  name        = "k8s-allow-internal"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow internal TCP, UDP, and ICMP across Kubernetes nodes and Pod networks"

  source_ranges = [var.subnet_cidr]
  target_tags   = [var.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }
}

# ------------------------------------------------------------------------------
# 2. Keyless SSH via Google Cloud Identity-Aware Proxy (IAP)
# ------------------------------------------------------------------------------
# Note: Allows SSH only from GCP's official IAP TCP forwarding netblock (35.235.240.0/20).
# Never opens SSH (port 22) to the public internet (0.0.0.0/0).
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "k8s-allow-iap-ssh"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow secure SSH tunneling through Google Cloud Identity-Aware Proxy"

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [var.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ------------------------------------------------------------------------------
# 3. Google Cloud Health Checks (For Load Balancer & Probes)
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "allow_health_checks" {
  name        = "k8s-allow-health-checks"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow Google Cloud health checks to reach Kubernetes API server"

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]
  target_tags = [var.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}
