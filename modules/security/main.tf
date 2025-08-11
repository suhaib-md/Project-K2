# Controller Security Group
resource "aws_security_group" "controller_sg" {
  name_prefix = "k8s-controller-"
  vpc_id      = var.vpc_id

  description = "Security group for Kubernetes controller nodes"

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes API server (allows direct access since no load balancer)
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP
  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.240.0.0/16"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "k8s-controller-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Separate rule for etcd communication between controllers
resource "aws_security_group_rule" "controller_etcd_client" {
  type                     = "ingress"
  from_port                = 2379
  to_port                  = 2380
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.controller_sg.id
  security_group_id        = aws_security_group.controller_sg.id
  description              = "etcd client API"
}

# Separate rule for controller to controller communication
resource "aws_security_group_rule" "controller_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.controller_sg.id
  security_group_id        = aws_security_group.controller_sg.id
  description              = "Controller internal communication"
}

# Worker Security Group
resource "aws_security_group" "worker_sg" {
  name_prefix = "k8s-worker-"
  vpc_id      = var.vpc_id

  description = "Security group for Kubernetes worker nodes"

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # kubelet API
  ingress {
    description     = "kubelet API"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.controller_sg.id]
  }

  # NodePort Services
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Pod network communication
  ingress {
    description = "Pod network"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.200.0.0/16"]
  }

  # ICMP
  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.240.0.0/16"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "k8s-worker-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Separate rule for worker to worker communication
resource "aws_security_group_rule" "worker_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.worker_sg.id
  security_group_id        = aws_security_group.worker_sg.id
  description              = "Worker internal communication"
}