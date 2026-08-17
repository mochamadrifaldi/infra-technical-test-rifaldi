variable "aws_region" {
  description = "AWS region tempat resource dideploy"
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.16.0.0/20"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the 2 public subnets"
  type        = list(string)
  default     = ["172.16.0.0/22", "172.16.4.0/22"]
}

variable "availability_zones" {
  description = "AZ for each public subnet"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "allowed_ssh_cidr" {
  description = "Workstation IP allowed to SSH into the instance (/32). Must be supplied via tfvars or environment variable — do not hardcode it here."
  type        = string
}

variable "instance_type" {
  description = "Tipe instance EC2"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Ukuran root volume GP3 dalam GB"
  type        = number
  default     = 33
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance (supply via tfvars, matching the region and desired OS)"
  type        = string
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair in the AWS account"
  type        = string
}

variable "environment" {
  description = "Environment name used for tagging"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used as a resource naming/tagging prefix"
  type        = string
  default     = "infra-tech-test"
}
