variable "aws_region" {
  type = string
}

variable "instance_type" {
  type    = string
}

variable "ubuntu_ami" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "harbor_hostname" {
  type = string
}

variable "harbor_admin_password" {
  type = string
}

variable "harbor_admin_email" {
  type = string
}

variable "harbor_https_port" {
  type = string
}

variable "harbor_http_port" {
  type = string
}

variable "harbor_ssl_cert_country" {
  type = string
}

variable "harbor_ssl_cert_state" {
  type = string
}

variable "harbor_ssl_cert_city" {
  type = string
}

variable "harbor_ssl_cert_organization" {
  type = string
}