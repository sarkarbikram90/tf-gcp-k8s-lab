variable "project_id" {
  description = "The GCP Project ID where the HA Kubernetes cluster will be deployed"
  type        = string
}

variable "region" {
  description = "GCP Region for all regional resources"
  type        = string
  default     = "asia-south2"
}

variable "zones" {
  description = "List of GCP Zones for multi-zone fault tolerance"
  type        = list(string)
  default     = ["asia-south2-a", "asia-south2-b", "asia-south2-c"]
}

variable "network_cidr" {
  description = "CIDR range for the Kubernetes HA subnetwork"
  type        = string
  default     = "10.10.0.0/24"
}

variable "cluster_name" {
  description = "Cluster prefix name for resources"
  type        = string
  default     = "k8s-ha"
}

variable "api_lb_ip" {
  description = "Static internal IP address within network_cidr reserved for the API Server Load Balancer"
  type        = string
  default     = "10.10.0.100"
}

variable "control_plane_machine_type" {
  description = "Machine type for control-plane nodes (e2-standard-2 provides 2 vCPU, 8 GB RAM)"
  type        = string
  default     = "e2-standard-2"
}

variable "worker_machine_type" {
  description = "Machine type for worker nodes (e2-medium provides 2 vCPU, 4 GB RAM)"
  type        = string
  default     = "e2-medium"
}

variable "assign_public_ip" {
  description = "Set to true only if you explicitly want public IPs. Default is false (Cloud NAT + IAP SSH)."
  type        = bool
  default     = false
}
