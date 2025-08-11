# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instances
resource "aws_instance" "instances" {
  count = var.instance_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = var.security_group_ids
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  
  user_data = var.user_data

  # Enable detailed monitoring
  monitoring = true

  # Enable source/destination checking (disable for workers if needed)
  source_dest_check = var.name_prefix == "worker" ? false : true

  # Root volume
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, {
      Name = "${var.name_prefix}-${count.index}-root"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${count.index}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Attach instances to target group if provided
resource "aws_lb_target_group_attachment" "tg_attachment" {
  count = var.target_group_arn != null ? var.instance_count : 0

  target_group_arn = var.target_group_arn
  target_id        = aws_instance.instances[count.index].id
  port             = 6443
}