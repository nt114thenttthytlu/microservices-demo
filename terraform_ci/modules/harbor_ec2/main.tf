resource "aws_instance" "harbor" {
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [var.sg_id]
  key_name = var.key_name
  ebs_optimized          = true
  monitoring = true
  metadata_options {
    http_tokens = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }
  user_data = file("${path.module}/install.sh")

  tags = {
    Name = "${var.name}-harbor"
  }
}