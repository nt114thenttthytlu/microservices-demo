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
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "key" {
  key_name   = "${var.name}-key"
  public_key = var.ssh_public_key
}

module "jenkins" {
  source = "./modules/jenkins"

  name          = var.name
  ami           = var.ami
  instance_type = "t3.micro"
  subnet_id     = module.network.subnet_id
  sg_id         = aws_security_group.main.id
  key_name      = aws_key_pair.key.key_name
}

module "harbor" {
  source = "./modules/harbor"

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
  instance_type = "t3.micro"
  subnet_id     = module.network.subnet_id
  sg_id         = aws_security_group.main.id
  key_name      = aws_key_pair.key.key_name
}