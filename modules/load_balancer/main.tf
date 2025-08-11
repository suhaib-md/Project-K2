# Network Load Balancer for Kubernetes API
resource "aws_lb" "k8s_api_lb" {
  name               = "k8s-api-lb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(var.tags, {
    Name = "k8s-api-lb"
  })
}

# Target Group for Kubernetes API
resource "aws_lb_target_group" "k8s_api_tg" {
  name     = "k8s-api-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
  }

  tags = merge(var.tags, {
    Name = "k8s-api-tg"
  })
}

# Listener for Kubernetes API
resource "aws_lb_listener" "k8s_api_listener" {
  load_balancer_arn = aws_lb.k8s_api_lb.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_api_tg.arn
  }

  tags = merge(var.tags, {
    Name = "k8s-api-listener"
  })
}