module "network" {
  source   = "./modules/network"
  name     = var.name
  vpc_cidr = var.vpc_cidr
  region   = var.region
}

resource "aws_security_group" "main" {
  name   = "${var.name}-sg"
  vpc_id = module.network.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr]
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [module.network.vpc_cidr]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-sg"
    description = "Security group for Jenkins, Harbor, and SonarQube instances"
  }
}

resource "aws_default_security_group" "this" {
  vpc_id = module.network.vpc_id

  ingress = []
  egress  = []
}

resource "aws_key_pair" "key" {
  key_name   = "${var.name}-key"
  public_key = var.ssh_public_key
}

module "jenkins" {
  source = "./modules/jenkins"

  name          = var.name
  ami           = var.ami
  instance_type = "c7i-flex.large"
  subnet_id     = module.network.subnet_id
  sg_id         = aws_security_group.main.id
  key_name      = aws_key_pair.key.key_name
}

module "harbor" {
  source = "./modules/harbor_ec2"

  name          = var.name
  ami           = var.ami
  instance_type = "t3.micro"
  subnet_id     = module.network.subnet_id
  sg_id         = aws_security_group.main.id
  key_name      = aws_key_pair.key.key_name
}

module "sonarqube" {
  source = "./modules/sonarqube"

  name          = var.name
  ami           = var.ami
  instance_type = "c7i-flex.large"
  subnet_id     = module.network.subnet_id
  sg_id         = aws_security_group.main.id
  key_name      = aws_key_pair.key.key_name
}


