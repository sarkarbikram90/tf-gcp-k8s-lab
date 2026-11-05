variable "project_id" {
  description = "The GCP Project ID where the hardened Kubernetes cluster will be deployed"
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
  description = "CIDR range for the hardened Kubernetes subnetwork"
  type        = string
  default     = "10.10.0.0/24"
}

variable "cluster_name" {
  description = "Cluster prefix name for resources"
  type        = string
  default     = "k8s-hardened"
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

variable "enable_kms" {
  description = "Whether to provision Cloud KMS for etcd secret encryption at rest"
  type        = bool
  default     = true
}

variable "enable_secret_manager" {
  description = "Whether to provision Google Secret Manager integration"
  type        = bool
  default     = true
}

variable "enable_gpu_worker_pool" {
  description = "Whether to provision an optional NVIDIA L4 GPU Spot worker node for Level 5 vLLM inference (disabled by default to avoid GPU billing)"
  type        = bool
  default     = false
}

variable "gpu_worker_machine_type" {
  description = "Machine type for the optional GPU worker node (g2-standard-4 includes 1x NVIDIA L4 24GB GPU)"
  type        = string
  default     = "g2-standard-4"
}

variable "gpu_accelerator_type" {
  description = "GCP GPU accelerator type attached to GPU worker nodes"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_worker_spot" {
  description = "Use Spot VMs (~60-70% discount) for the GPU worker pool"
  type        = bool
  default     = true
}
