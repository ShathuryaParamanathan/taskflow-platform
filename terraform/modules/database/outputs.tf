output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.this.address
}
output "db_port" {
  value = aws_db_instance.this.port
}
output "db_name" {
  value = aws_db_instance.this.db_name
}
