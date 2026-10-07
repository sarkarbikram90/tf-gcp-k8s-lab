# ------------------------------------------------------------------------------
# 1. Custom Isolated VPC & Subnetwork (Zero Default Network)
# ------------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  network_name = "${var.cluster_name}-vpc"
  subnet_name  = "${var.cluster_name}-subnet"
  region       = var.region
  subnet_cidr  = var.network_cidr
}

# ------------------------------------------------------------------------------
# 2. Cloud Router & Cloud NAT Gateway (Brokered Outbound Egress)
# ------------------------------------------------------------------------------
module "nat" {
  source = "../../modules/nat"

  name       = var.cluster_name
  network_id = module.network.network_id
  region     = var.region
  subnet_id  = module.network.subnet_id
}

# ------------------------------------------------------------------------------
# 3. Least-Privilege Node Runtime Service Account
# ------------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  project_id         = var.project_id
  service_account_id = "${var.cluster_name}-node-sa"
}

# ------------------------------------------------------------------------------
# 4. Cloud KMS for etcd Secrets Encryption at Rest
# ------------------------------------------------------------------------------
module "kms" {
  count  = var.enable_kms ? 1 : 0
  source = "../../modules/kms"

  key_ring_name         = "${var.cluster_name}-keyring"
  crypto_key_name       = "k8s-secrets-encryption-key"
  region                = var.region
  service_account_email = module.iam.service_account_email
}

# ------------------------------------------------------------------------------
# 5. Google Cloud Secret Manager (Externalized Application Secrets)
# ------------------------------------------------------------------------------
module "secret_manager" {
  count  = var.enable_secret_manager ? 1 : 0
  source = "../../modules/secret-manager"

  secret_id             = "${var.cluster_name}-database-credentials"
  service_account_email = module.iam.service_account_email
}

# ------------------------------------------------------------------------------
# 6. Zero-Trust Fine-Grained Firewall Rules (Strict Mode Enforced)
# ------------------------------------------------------------------------------
# Enforces etcd isolation to control plane nodes only, limits Kubelet API caller,
# and isolates CNI, CoreDNS, and NodePort ports. No open 0-65535 rules.
module "firewall" {
  source = "../../modules/firewall"

  network_name      = module.network.network_name
  subnet_cidr       = module.network.subnet_cidr
  node_tag          = "k8s-node"
  control_plane_tag = "k8s-control-plane"
  worker_tag        = "k8s-worker"
  strict_mode       = true
}

# ------------------------------------------------------------------------------
# 7. Multi-Zone Private Nodes (3 Control Planes + 3 Workers)
# ------------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  name_prefix           = var.cluster_name
  network_id            = module.network.network_id
  subnet_id             = module.network.subnet_id
  service_account_email = module.iam.service_account_email
  assign_public_ip      = false # Zero public IPs strictly enforced

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
# 8. Regional Internal TCP Load Balancer for Kubernetes API Server (:6443)
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
