resource "aws_security_group" "node" {
  name        = "${var.name_prefix}-node-sg"
  description = "k3s node security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-node-sg"
  }
}

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.node.id
  description       = "SSH"
}

resource "aws_security_group_rule" "k8s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.node.id
  description       = "Kubernetes API (k3s)"
}

resource "aws_security_group_rule" "app_nodeport" {
  type              = "ingress"
  from_port         = var.app_node_port
  to_port           = var.app_node_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
  description       = "App NodePort"
}

resource "aws_security_group_rule" "node_to_node" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.node.id
  security_group_id        = aws_security_group.node.id
  description              = "All traffic between cluster nodes (k3s API, flannel VXLAN, kubelet)"
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
  description       = "All outbound"
}
