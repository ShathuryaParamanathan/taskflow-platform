resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-db-subnets" })
}
resource "aws_db_instance" "this" {
  identifier              = "${var.name}-postgres"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = var.instance_class
  allocated_storage       = 20
  max_allocated_storage   = 50
  storage_type            = "gp3"
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  port                    = 5432
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [var.database_security_group_id]
  publicly_accessible     = false
  storage_encrypted       = true
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  tags                    = merge(var.tags, { Name = "${var.name}-postgres" })
}
