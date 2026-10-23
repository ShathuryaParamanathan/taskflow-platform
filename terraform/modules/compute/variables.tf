variable "name" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  type = list(string)
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "alb_security_group_id" {
  type = string
}
variable "ecs_security_group_id" {
  type = string
}
variable "container_port" {
  type    = number
  default = 3000
}
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "image_tag" {
  description = "TaskFlow API Docker image tag"
  type        = string
  default     = "latest"
}
variable "db_endpoint" {
  type = string
}
variable "db_name" {
  type    = string
  default = "taskflow"
}
variable "db_username" {
  type      = string
  sensitive = true
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "task_cpu" {
  description = "ECS task CPU units; 256 = 0.25 vCPU"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "ECS task memory in MiB"
  type        = number
  default     = 512
}