variable "name" {
  description = "Name prefix for the load balancer resources"
  type        = string
  default     = "k8s-ha"
}

variable "region" {
  description = "GCP region for regional load balancer resources"
  type        = string
}

variable "network_id" {
  description = "The ID of the VPC network"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnetwork where the forwarding rule will reside"
  type        = string
}

variable "control_plane_instances" {
  description = "List of control plane instance objects containing self_link and zone"
  type = list(object({
    self_link = string
    zone      = string
  }))
}

variable "api_lb_ip" {
  description = "Optional static internal IP within subnet CIDR for the load balancer (if null, GCP allocates an ephemeral IP)"
  type        = string
  default     = null
}
