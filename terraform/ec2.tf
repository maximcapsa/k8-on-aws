data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Shared cluster join token so servers can form the etcd cluster without us
# having to read the dynamically generated node-token back out.
resource "random_password" "k3s_token" {
  length  = 40
  special = false
}

# --- k3s server #0: initializes the embedded-etcd cluster + bootstraps ArgoCD ---
resource "aws_instance" "server_init" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  associate_public_ip_address = true
  key_name                    = var.key_name != "" ? var.key_name : null
  iam_instance_profile        = aws_iam_instance_profile.node.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data_server_init.sh.tpl", {
    token          = random_password.k3s_token.result
    argo_app_url   = "https://raw.githubusercontent.com/${var.github_repo}/${var.github_branch}/argo/application.yaml"
    ecr_cp_version = var.ecr_credential_provider_version
  })
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name_prefix}-server-0"
    Role = "k3s-server"
  }
}

# --- additional servers: join the etcd cluster (server_count - 1 of them) ---
resource "aws_instance" "server_join" {
  count                       = var.server_count - 1
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.node.id]
  associate_public_ip_address = true
  key_name                    = var.key_name != "" ? var.key_name : null
  iam_instance_profile        = aws_iam_instance_profile.node.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data_server_join.sh.tpl", {
    token          = random_password.k3s_token.result
    server_ip      = aws_instance.server_init.private_ip
    ecr_cp_version = var.ecr_credential_provider_version
  })
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name_prefix}-server-${count.index + 1}"
    Role = "k3s-server"
  }
}
