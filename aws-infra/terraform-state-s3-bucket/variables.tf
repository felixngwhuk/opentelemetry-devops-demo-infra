variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "terraform_state_bucket" {
  description = "Name of the S3 bucket used for Terraform state"
  type        = string
  default     = "felixngwhuk-terraform-eks-state-s3-bucket"
}
