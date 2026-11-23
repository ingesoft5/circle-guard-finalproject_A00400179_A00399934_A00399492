data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "ci" {
  name        = "${var.name}-ci"
  description = "Jenkins server"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-ci-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ci.id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "jenkins" {
  security_group_id = aws_security_group.ci.id
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ci.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_key_pair" "ci" {
  key_name   = "${var.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_iam_role" "ci" {
  name = "${var.name}-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ci" {
  name   = "${var.name}-ci"
  role   = aws_iam_role.ci.id
  policy = var.iam_policy_json
}

resource "aws_iam_instance_profile" "ci" {
  name = "${var.name}-ci"
  role = aws_iam_role.ci.name
}

resource "aws_eip" "ci" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-ci-eip"
  }
}

resource "aws_instance" "ci" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.ci.id]
  iam_instance_profile        = aws_iam_instance_profile.ci.name
  key_name                    = aws_key_pair.ci.key_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    terraform_version = var.terraform_version
  })

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  lifecycle {
    ignore_changes = [associate_public_ip_address, ami]
  }

  tags = {
    Name = "${var.name}-jenkins"
  }
}

resource "aws_eip_association" "ci" {
  instance_id   = aws_instance.ci.id
  allocation_id = aws_eip.ci.id
}
