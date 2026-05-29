variable "name" {}
variable "environment" {}
variable "vpc_cidr" {}
variable "azs" {
  type = list(string)
}