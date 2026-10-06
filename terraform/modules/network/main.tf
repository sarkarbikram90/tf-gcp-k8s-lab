resource "google_compute_network" "k8s_vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  description             = "Dedicated VPC network for self-managed Kubernetes cluster"
}

resource "google_compute_subnetwork" "k8s_subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.k8s_vpc.id
  private_ip_google_access = true
  description              = "Subnetwork for Kubernetes control plane and worker nodes"
}
