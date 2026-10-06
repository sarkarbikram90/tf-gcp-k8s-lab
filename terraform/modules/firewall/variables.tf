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
