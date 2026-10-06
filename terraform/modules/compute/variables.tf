variable "name_prefix" {
  description = "Prefix for instance names"
  type        = string
  default     = "k8s"
}

variable "instances" {
  description = "Map of VM instances to provision with their role and machine specs"
  type = map(object({
    role         = string
    machine_type = string
    disk_size_gb = optional(number, 30)
    zone         = string
  }))
}

variable "os_image" {
  description = "Source OS image for VM boot disk"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "boot_disk_type" {
  description = "GCP persistent disk type"
  type        = string
  default     = "pd-balanced"
}

variable "network_id" {
  description = "ID of the VPC network"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnetwork"
  type        = string
}

variable "service_account_email" {
  description = "Service account to attach to the VMs"
  type        = string
}

variable "assign_public_ip" {
  description = "Whether to assign ephemeral public IPs to the nodes (false keeps nodes strictly private)"
  type        = bool
  default     = false
}
