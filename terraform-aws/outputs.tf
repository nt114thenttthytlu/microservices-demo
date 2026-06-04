output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${var.eks_cluster_name} --region ${var.region}"
}