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

resource "aws_flow_log" "this" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = module.network.vpc_id

  iam_role_arn = aws_iam_role.flowlog.arn
}

resource "aws_iam_role" "flowlog" {
  name = "${var.name}-flowlog-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "flowlog" {
  role       = aws_iam_role.flowlog.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonVPCFlowLogsRole"
}

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/aws/vpc/flowlogs"
  retention_in_days = 7
}