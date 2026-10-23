variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "ap-south-1"
}
variable "project_name" {
  description = "Project resource prefix"
  type        = string
  default     = "taskflow"
}
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
variable "db_username" {
  description = "RDS database username"
  type        = string
  sensitive   = true
}
variable "db_password" {
  description = "RDS database password; supply securely at deployment time"
  type        = string
  sensitive   = true
}

variable "task_cpu" {
  description = "ECS task CPU units"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "ECS task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS tasks to run during deployment"
  type        = number
  default     = 0
}

variable "image_tag" {
  description = "Docker image tag for the ECS deployment (Git commit SHA)"
  type        = string
  default     = "latest"
}
