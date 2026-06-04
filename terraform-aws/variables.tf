variable "region" {
  default = "ap-southeast-1"
}

variable "environment" {
  default = "dev"
}

variable "name" {
  default = "microservices-demo"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "eks_cluster_name" {
  default = "eks-microservices"
}

variable "eks_cluster_version" {
  default = "1.30"
}

variable "node_group_desired_size" {
  default = 2
}

variable "node_group_min_size" {
  default = 2
}

variable "node_group_max_size" {
  default = 4
}

variable "instance_types" {
  default = ["t3.micro"]
}