output "aws_region" {
  description = "AWS deployment region"
  value       = var.aws_region
}
output "resource_prefix" {
  description = "Project resource prefix"
  value       = local.name
}
output "vpc_id" {
  description = "TaskFlow VPC ID"
  value       = module.network.vpc_id
}
output "ecr_repository_url" {
  description = "TaskFlow Docker image repository"
  value       = module.compute.ecr_repository_url
}
output "db_endpoint" {
  description = "Private PostgreSQL endpoint"
  value       = module.database.db_endpoint
}
