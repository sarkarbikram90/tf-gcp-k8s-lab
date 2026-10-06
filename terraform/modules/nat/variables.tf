variable "name" {
  description = "Prefix name for the Cloud Router and NAT gateway"
  type        = string
  default     = "k8s-lab"
}

variable "network_id" {
  description = "The ID of the VPC network"
  type        = string
}

variable "region" {
  description = "GCP region where Cloud Router and NAT will operate"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet to provide NAT service for"
  type        = string
}
