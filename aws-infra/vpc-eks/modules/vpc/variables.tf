variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one availability zone."
  }
}

variable "private_subnet_cidrs" {
  description = "Optional CIDR blocks for private subnets. When null, one /24 subnet is generated per availability zone."
  type        = list(string)
  default     = null

  validation {
    condition     = var.private_subnet_cidrs == null || length(var.private_subnet_cidrs) == length(var.availability_zones)
    error_message = "private_subnet_cidrs must be null or contain one CIDR block per availability zone."
  }
}

variable "public_subnet_cidrs" {
  description = "Optional CIDR blocks for public subnets. When null, one /24 subnet is generated per availability zone."
  type        = list(string)
  default     = null

  validation {
    condition     = var.public_subnet_cidrs == null || length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "public_subnet_cidrs must be null or contain one CIDR block per availability zone."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}
