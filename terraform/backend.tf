terraform {
  backend "s3" {
    bucket       = "taskflow-terraform-state-440744236554-ap-south-1"
    key          = "taskflow/dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
