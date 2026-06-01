variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
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

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs"
  type        = list(string)
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
}

variable "bastion_role_name" {
  description = "Name of the IAM role attached to the EC2 bastion host"
  type        = string
  default     = "EC2BastionAdminRole"
}
