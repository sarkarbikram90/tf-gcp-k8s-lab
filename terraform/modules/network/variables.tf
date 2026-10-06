variable "network_name" {
  description = "Name of the custom VPC network"
  type        = string
  default     = "k8s-lab-vpc"
}

variable "subnet_name" {
  description = "Name of the dedicated Kubernetes subnet"
  type        = string
  default     = "k8s-lab-subnet"
}

variable "region" {
  description = "GCP region where the subnet will be created"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the Kubernetes subnet"
  type        = string
  default     = "10.10.0.0/24"
}
