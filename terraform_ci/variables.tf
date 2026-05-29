variable "region" { default = "ap-southeast-1" }
variable "name" { default = "microservices-demo" }
variable "vpc_cidr" { default = "10.0.0.0/16" }
variable "ami" { default = "ami-0a56f8447277affd8" }
variable "ssh_public_key" {}