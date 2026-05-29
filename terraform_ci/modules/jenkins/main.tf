provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "jenkins-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "jenkins-igw"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "jenkins-subnet"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "jenkins-rt"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "sg" {
  name        = "jenkins-sg"
  description = "Allow Jenkins, SSH, Harbor"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Harbor HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Harbor HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Harbor Registry"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-sg"
  }
}

resource "aws_key_pair" "key" {
  key_name   = "jenkins-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "vm" {
  ami                    = var.ubuntu_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.sg.id]
  key_name               = aws_key_pair.key.key_name

  user_data = templatefile("${path.module}/installing_jenkins.sh", {
    harbor_hostname              = var.harbor_hostname
    harbor_admin_password        = var.harbor_admin_password
    harbor_admin_email           = var.harbor_admin_email
    harbor_https_port            = var.harbor_https_port
    harbor_http_port             = var.harbor_http_port
    harbor_ssl_cert_country      = var.harbor_ssl_cert_country
    harbor_ssl_cert_state        = var.harbor_ssl_cert_state
    harbor_ssl_cert_city         = var.harbor_ssl_cert_city
    harbor_ssl_cert_organization = var.harbor_ssl_cert_organization
  })

  tags = {
    Name = "jenkins-vm"
  }
}

resource "aws_eip" "eip" {
  instance = aws_instance.vm.id
  domain   = "vpc"

  tags = {
    Name = "jenkins-eip"
  }
}