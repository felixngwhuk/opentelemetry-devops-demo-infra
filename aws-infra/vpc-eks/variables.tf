variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Optional CIDR blocks for private subnets. When null, one /24 subnet is generated per availability zone in the selected region."
  type        = list(string)
  default     = null
}

variable "public_subnet_cidrs" {
  description = "Optional CIDR blocks for public subnets. When null, one /24 subnet is generated per availability zone in the selected region."
  type        = list(string)
  default     = null
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "my-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "cluster_authentication_mode" {
  description = "EKS cluster authentication mode. Access entries require API or API_AND_CONFIG_MAP."
  type        = string
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.cluster_authentication_mode)
    error_message = "cluster_authentication_mode must be either API or API_AND_CONFIG_MAP."
  }
}

variable "node_groups" {
  description = "EKS node group configuration"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
  }))
  default = {
    general = {
      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      scaling_config = {
        desired_size = 3
        max_size     = 4
        min_size     = 1
      }
    }
  }
}
