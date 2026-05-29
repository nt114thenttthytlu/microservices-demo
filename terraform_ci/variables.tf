variable "aws_region" {
  default = "ap-southeast-1"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "ubuntu_ami" {
  description = "Ubuntu 24.04 AMI"

  default = "ami-0a56f8447277affd8"
}

variable "ssh_public_key" {
  description = "Your SSH public key"
  type        = string
}

# ============ Harbor Configuration ============

variable "harbor_hostname" {
  description = "Harbor hostname or IP address (if empty, will use public IP automatically)"
  type        = string
  default     = ""
}

variable "harbor_admin_password" {
  description = "Harbor admin password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.harbor_admin_password) >= 8
    error_message = "Harbor admin password must be at least 8 characters long."
  }
}

variable "harbor_admin_email" {
  description = "Harbor admin email"
  type        = string
  default     = "admin@example.com"
}

variable "harbor_https_port" {
  description = "Harbor HTTPS port"
  type        = number
  default     = 443
}

variable "harbor_http_port" {
  description = "Harbor HTTP port"
  type        = number
  default     = 80
}

variable "harbor_ssl_cert_country" {
  description = "SSL certificate country code"
  type        = string
  default     = "VN"
}

variable "harbor_ssl_cert_state" {
  description = "SSL certificate state"
  type        = string
  default     = "HaNoi"
}

variable "harbor_ssl_cert_city" {
  description = "SSL certificate city"
  type        = string
  default     = "Ho Chi Minh City"
}

variable "harbor_ssl_cert_organization" {
  description = "SSL certificate organization"
  type        = string
  default     = "Organization"
}