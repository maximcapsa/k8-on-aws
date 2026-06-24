variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to resource names/tags"
  type        = string
  default     = "k8s-on-aws"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the k3s nodes (t2.micro is free-tier eligible in most regions)"
  type        = string
  default     = "t2.micro"
}

variable "server_count" {
  description = "Number of k3s server nodes (embedded-etcd HA). Use an odd number; 3 gives a fault-tolerant control plane. NOTE: multiple t2.micros 24/7 exceed the 750h/mo free tier."
  type        = number
  default     = 3

  validation {
    condition     = var.server_count >= 1
    error_message = "server_count must be at least 1 (use 1 or 3; 3 for HA quorum)."
  }
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB (free tier allows up to 30 GiB)"
  type        = number
  default     = 30
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access. Leave empty to launch without SSH."
  type        = string
  default     = ""
}

variable "admin_cidr" {
  description = "CIDR allowed to reach SSH (22) and the Kubernetes API (6443). Restrict to your IP, e.g. 1.2.3.4/32."
  type        = string
  default     = "0.0.0.0/0"
}

variable "app_node_port" {
  description = "NodePort the app is exposed on (must be in 30000-32767)"
  type        = number
  default     = 30080
}

variable "github_repo" {
  description = "GitHub repo in owner/name form, used to fetch the Argo CD Application during bootstrap"
  type        = string
  default     = "maximcapsa/k8-on-aws"
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository for the app image"
  type        = string
  default     = "myapp"
}

variable "ecr_credential_provider_version" {
  description = "Release tag of kubernetes/cloud-provider-aws to fetch the ecr-credential-provider binary from (lets k3s pull from private ECR)"
  type        = string
  default     = "v1.31.0"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub Actions OIDC provider. Set false if your account already has one (only one per account is allowed)."
  type        = bool
  default     = true
}

variable "github_branch" {
  description = "Branch Argo CD / bootstrap tracks"
  type        = string
  default     = "master"
}
