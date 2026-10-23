variable "name" {
  type = string
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "database_security_group_id" {
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
variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "tags" {
  type    = map(string)
  default = {}
}
