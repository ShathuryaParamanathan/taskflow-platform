output "ecr_repository_url" {
  description = "Docker image repository URL"
  value       = aws_ecr_repository.this.repository_url
}
