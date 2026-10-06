variable "project_id" {
  description = "The GCP Project ID where the Kubernetes lab will be deployed"
  type        = string
}

variable "region" {
  description = "GCP Region for all regional resources"
  type        = string
  default     = "asia-south2"
}

variable "zone" {
  description = "GCP Zone for the VM compute instances"
  type        = string
  default     = "asia-south2-a"
}

variable "network_cidr" {
  description = "CIDR range for the Kubernetes lab subnetwork"
  type        = string
  default     = "10.10.0.0/24"
}

variable "cluster_name" {
  description = "Cluster prefix name for resources"
  type        = string
  default     = "k8s-lab"
}

variable "control_plane_machine_type" {
  description = "Machine type for the control-plane node (requires at least 2 vCPU and 2 GB RAM; e2-standard-2 provides 2 vCPU, 8 GB)"
  type        = string
  default     = "e2-standard-2"
}

variable "worker_machine_type" {
  description = "Machine type for worker nodes (e2-medium provides 2 vCPU, 4 GB)"
  type        = string
  default     = "e2-medium"
}

variable "assign_public_ip" {
  description = "Set to true only if you explicitly want public IPs on VMs. Default is false (uses Cloud NAT + IAP SSH for zero-exposure security)."
  type        = bool
  default     = false
}
