# ------------------------------------------------------------------------------
# 1. Baseline Internal Subnet Traffic (Permissive mode for Level 1 & 2 labs)
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  count = var.strict_mode ? 0 : 1

  name        = "k8s-allow-internal"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow internal TCP, UDP, and ICMP across Kubernetes nodes (permissive lab mode)"

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
# 2. Strict Zero-Trust Granular Ingress Rules (Level 3 Hardened)
# ------------------------------------------------------------------------------

# etcd: ONLY accessible between Control Plane instances (2379: client, 2380: peer)
resource "google_compute_firewall" "strict_etcd" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-etcd"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Restrict etcd communication strictly to control plane nodes"

  source_tags = [var.control_plane_tag]
  target_tags = [var.control_plane_tag]

  allow {
    protocol = "tcp"
    ports    = ["2379-2380"]
  }
}

# Kubernetes API server: Accessible from the subnet (workers & clients) & health checks
resource "google_compute_firewall" "strict_apiserver" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-apiserver"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow port 6443 to control plane nodes from subnet and health checks"

  source_ranges = [
    var.subnet_cidr,
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]
  target_tags = [var.control_plane_tag]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

# Kubelet API: Port 10250 allowed only from control-plane nodes
resource "google_compute_firewall" "strict_kubelet" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-kubelet"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow Kubelet API access strictly from control plane nodes"

  source_tags = [var.control_plane_tag]
  target_tags = [var.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }
}

# Control plane internal components (kube-controller-manager: 10257, kube-scheduler: 10259)
resource "google_compute_firewall" "strict_cp_components" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-cp-components"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow control plane component health endpoints strictly on control plane"

  source_tags = [var.control_plane_tag]
  target_tags = [var.control_plane_tag]

  allow {
    protocol = "tcp"
    ports    = ["10257", "10259"]
  }
}

# CNI Overlay traffic (Flannel VXLAN UDP 8472 & Calico BGP TCP 179)
resource "google_compute_firewall" "strict_cni_overlay" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-cni-overlay"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow CNI overlay network traffic between all cluster nodes"

  source_tags = [var.node_tag]
  target_tags = [var.node_tag]

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }

  allow {
    protocol = "tcp"
    ports    = ["179"]
  }
}

# CoreDNS: DNS queries (TCP & UDP 53) within the cluster
resource "google_compute_firewall" "strict_coredns" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-coredns"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow CoreDNS resolution across cluster nodes"

  source_tags = [var.node_tag]
  target_tags = [var.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }

  allow {
    protocol = "udp"
    ports    = ["53"]
  }
}

# NodePort services (30000-32767) to workers within the subnet
resource "google_compute_firewall" "strict_nodeports" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-nodeports"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow NodePort traffic to worker nodes from within the subnet"

  source_ranges = [var.subnet_cidr]
  target_tags   = [var.worker_tag]

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }
}

# ICMP (Ping) within subnet for network diagnostics
resource "google_compute_firewall" "strict_icmp" {
  count = var.strict_mode ? 1 : 0

  name        = "k8s-strict-icmp"
  network     = var.network_name
  direction   = "INGRESS"
  priority    = 900
  description = "Allow ICMP within the subnet for health checks and diagnostics"

  source_ranges = [var.subnet_cidr]
  target_tags   = [var.node_tag]

  allow {
    protocol = "icmp"
  }
}

# ------------------------------------------------------------------------------
# 3. Always Enforced: Keyless SSH via Google Cloud IAP (35.235.240.0/20)
# ------------------------------------------------------------------------------
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
# 4. Google Cloud Health Checks (Load Balancer & Regional Probes)
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "allow_health_checks" {
  count = var.strict_mode ? 0 : 1

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
