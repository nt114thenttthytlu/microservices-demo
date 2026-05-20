module "vpc" {
  source = "./modules/vpc"

  project_name = var.name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  region       = var.region
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.name
  environment  = var.environment
}

module "eks" {
  source = "./modules/eks"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.eks_cluster_version
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  environment     = var.environment
  project_name    = var.name

  node_group_desired_size = var.node_group_desired_size
  node_group_min_size     = var.node_group_min_size
  node_group_max_size     = var.node_group_max_size
  instance_types          = var.instance_types
}