variable "network_name" {
  description = "The name of the VPC network to attach firewall rules to"
  type        = string
}

variable "subnet_cidr" {
  description = "The CIDR block of the Kubernetes subnet"
  type        = string
}

variable "node_tag" {
  description = "Target network tag applied to all Kubernetes VM nodes"
  type        = string
  default     = "k8s-node"
}

variable "control_plane_tag" {
  description = "Network tag applied to control plane nodes"
  type        = string
  default     = "k8s-control-plane"
}

variable "worker_tag" {
  description = "Network tag applied to worker nodes"
  type        = string
  default     = "k8s-worker"
}

variable "strict_mode" {
  description = "If true, enforces granular port-level rules (etcd isolated to CPs, kubelet from CPs only, CNI overlay restricted) instead of wide subnet ingress"
  type        = bool
  default     = false
}
