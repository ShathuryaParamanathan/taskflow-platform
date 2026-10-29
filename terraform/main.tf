locals {
  name = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
module "network" {
  source = "./modules/network"
  name   = local.name
  tags   = local.common_tags
}
module "security" {
  source         = "./modules/security"
  name           = local.name
  vpc_id         = module.network.vpc_id
  container_port = 3000
  tags           = local.common_tags
}
module "database" {
  source                     = "./modules/database"
  name                       = local.name
  private_subnet_ids         = module.network.private_subnet_ids
  database_security_group_id = module.security.database_security_group_id
  db_name                    = "taskflow"
  db_username                = var.db_username
  db_password                = var.db_password
  tags                       = local.common_tags
}
module "compute" {
  source                = "./modules/compute"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  ecs_security_group_id = module.security.ecs_security_group_id
  container_port        = 3000
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  db_endpoint           = module.database.db_endpoint
  db_username           = var.db_username
  db_password           = var.db_password
  tags                  = local.common_tags
  desired_count         = var.desired_count
  image_tag             = var.image_tag
  ecs_ami_id            = var.ecs_ami_id
}
