# ------------------------------------------------------------------------------
# 1. Custom VPC & Subnetwork
# ------------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  network_name = "${var.cluster_name}-vpc"
  subnet_name  = "${var.cluster_name}-subnet"
  region       = var.region
  subnet_cidr  = var.network_cidr
}

# ------------------------------------------------------------------------------
# 2. Cloud Router & Cloud NAT Gateway (Secure Egress for Private Nodes)
# ------------------------------------------------------------------------------
module "nat" {
  source = "../../modules/nat"

  name       = var.cluster_name
  network_id = module.network.network_id
  region     = var.region
  subnet_id  = module.network.subnet_id
}

# ------------------------------------------------------------------------------
# 3. Least-Privilege Node Service Account
# ------------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  project_id         = var.project_id
  service_account_id = "${var.cluster_name}-node-sa"
}

# ------------------------------------------------------------------------------
# 4. Firewall Rules (Internal Cluster Traffic + IAP SSH)
# ------------------------------------------------------------------------------
module "firewall" {
  source = "../../modules/firewall"

  network_name = module.network.network_name
  subnet_cidr  = module.network.subnet_cidr
  node_tag     = "k8s-node"
}

# ------------------------------------------------------------------------------
# 5. Kubernetes Nodes (1 Control Plane + 2 Workers)
# ------------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  name_prefix           = var.cluster_name
  network_id            = module.network.network_id
  subnet_id             = module.network.subnet_id
  service_account_email = module.iam.service_account_email
  assign_public_ip      = var.assign_public_ip

  instances = {
    "control-plane" = {
      role         = "control-plane"
      machine_type = var.control_plane_machine_type
      disk_size_gb = 30
      zone         = var.zone
    }
    "worker-01" = {
      role         = "worker"
      machine_type = var.worker_machine_type
      disk_size_gb = 30
      zone         = var.zone
    }
    "worker-02" = {
      role         = "worker"
      machine_type = var.worker_machine_type
      disk_size_gb = 30
      zone         = var.zone
    }
  }

  depends_on = [module.nat]
}
