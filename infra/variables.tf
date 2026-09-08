variable "name_prefix" {
  description = "Prefix for every resource name, so multiple deployments can share a project."
  type        = string
  default     = "lsa"
}

variable "external_network_name" {
  description = "Name of the provider's external (public) network. On Switch Engines this is typically 'public'."
  type        = string
  default     = "public"
}

variable "subnet_cidr" {
  description = "CIDR of the private subnet the instances live in."
  type        = string
  default     = "10.10.10.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "dns_nameservers" {
  description = "DNS resolvers handed out on the subnet."
  type        = list(string)
  default     = ["9.9.9.9", "149.112.112.112"]
}

variable "image_name" {
  description = "Glance image for the instances (an Ubuntu LTS image name as published by the cloud)."
  type        = string
  default     = "Ubuntu 24.04 LTS"
}

variable "flavor_name" {
  description = "Compute flavor for the application instance."
  type        = string
  default     = "m1.small"
}

variable "db_flavor_name" {
  description = "Compute flavor for the database instance."
  type        = string
  default     = "m1.small"
}

variable "public_key" {
  description = "SSH public key material for the operator keypair. Only the public half — the private key never touches Terraform."
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to reach SSH on the app instance. Default deliberately requires an explicit decision instead of 0.0.0.0/0."
  type        = string

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "Refusing SSH open to the whole internet; pass a concrete admin network CIDR."
  }
}
