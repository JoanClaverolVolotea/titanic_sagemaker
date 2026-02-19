locals {
  required_tags = {
    project     = var.project
    env         = var.environment
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = var.cost_center
  }
}
