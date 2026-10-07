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
# 2. Cloud Router & Cloud NAT Gateway (Outbound Internet for Private VMs)
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
# 4. Firewall Rules (Internal Traffic + IAP SSH + Health Checks)
# ------------------------------------------------------------------------------
module "firewall" {
  source = "../../modules/firewall"

  network_name = module.network.network_name
  subnet_cidr  = module.network.subnet_cidr
  node_tag     = "k8s-node"
}

# ------------------------------------------------------------------------------
# 5. Multi-Zone Kubernetes Nodes (3 Control Planes + 3 Workers)
# ------------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  name_prefix           = var.cluster_name
  network_id            = module.network.network_id
  subnet_id             = module.network.subnet_id
  service_account_email = module.iam.service_account_email
  assign_public_ip      = var.assign_public_ip

  instances = {
    # 3 Control Plane nodes distributed across failure domains
    "cp-01" = {
      role         = "control-plane"
      machine_type = var.control_plane_machine_type
      disk_size_gb = 30
      zone         = var.zones[0]
    }
    "cp-02" = {
      role         = "control-plane"
      machine_type = var.control_plane_machine_type
      disk_size_gb = 30
      zone         = var.zones[1 % length(var.zones)]
    }
    "cp-03" = {
      role         = "control-plane"
      machine_type = var.control_plane_machine_type
      disk_size_gb = 30
      zone         = var.zones[2 % length(var.zones)]
    }

    # 3 Worker nodes
    "worker-01" = {
      role         = "worker"
      machine_type = var.worker_machine_type
      disk_size_gb = 30
      zone         = var.zones[0]
    }
    "worker-02" = {
      role         = "worker"
      machine_type = var.worker_machine_type
      disk_size_gb = 30
      zone         = var.zones[1 % length(var.zones)]
    }
    "worker-03" = {
      role         = "worker"
      machine_type = var.worker_machine_type
      disk_size_gb = 30
      zone         = var.zones[2 % length(var.zones)]
    }
  }

  depends_on = [module.nat]
}

# ------------------------------------------------------------------------------
# 6. Regional Internal TCP Load Balancer for Kubernetes API Server (:6443)
# ------------------------------------------------------------------------------
module "load_balancer" {
  source = "../../modules/load-balancer"

  name       = var.cluster_name
  region     = var.region
  network_id = module.network.network_id
  subnet_id  = module.network.subnet_id
  api_lb_ip  = var.api_lb_ip

  control_plane_instances = [
    for k, inst in module.compute.instances : {
      self_link = inst.self_link
      zone      = inst.zone
    }
    if startswith(k, "cp-")
  ]
}
