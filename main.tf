terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate SSH key pair
resource "tls_private_key" "k8s_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s_key_pair" {
  key_name   = "k8s-the-hard-way"
  public_key = tls_private_key.k8s_key.public_key_openssh
}

# Save private key locally
resource "local_file" "private_key" {
  content  = tls_private_key.k8s_key.private_key_pem
  filename = "${path.module}/k8s-key.pem"
  file_permission = "0600"
}

# Network module
module "networking" {
  source = "./modules/networking"
  
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  
  tags = var.common_tags
}

# Security groups module
module "security" {
  source = "./modules/security"
  
  vpc_id = module.networking.vpc_id
  
  tags = var.common_tags
}

# Controller nodes module (reduced to 1 for vCPU limits)
module "controllers" {
  source = "./modules/compute"
  
  instance_count     = 1  # Reduced from 3 to 1
  instance_type     = var.controller_instance_type
  key_name          = aws_key_pair.k8s_key_pair.key_name
  security_group_ids = [module.security.controller_security_group_id]
  subnet_ids        = module.networking.public_subnet_ids
  
  name_prefix = "controller"
  user_data   = file("${path.module}/scripts/controller-userdata.sh")
  
  attach_to_target_group = false
  
  tags = merge(var.common_tags, {
    Role = "controller"
  })
}

# Worker nodes module (reduced to 2 for vCPU limits)
module "workers" {
  source = "./modules/compute"
  
  instance_count     = 2  # Reduced from 3 to 2
  instance_type     = var.worker_instance_type
  key_name          = aws_key_pair.k8s_key_pair.key_name
  security_group_ids = [module.security.worker_security_group_id]
  subnet_ids        = module.networking.public_subnet_ids
  
  name_prefix = "worker"
  user_data   = file("${path.module}/scripts/worker-userdata.sh")
  
  attach_to_target_group = false
  
  tags = merge(var.common_tags, {
    Role = "worker"
  })
}

# Generate inventory and configuration files
resource "local_file" "inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    controllers = module.controllers.instances
    workers     = module.workers.instances
    lb_dns      = module.controllers.instances[0].public_ip
  })
  filename = "${path.module}/inventory.ini"
}

resource "local_file" "ssh_config" {
  content = templatefile("${path.module}/templates/ssh_config.tpl", {
    controllers = module.controllers.instances
    workers     = module.workers.instances
    private_key = "${path.module}/k8s-key.pem"
  })
  filename = "${path.module}/ssh_config"
}

# Trigger the setup script
resource "null_resource" "setup_kubernetes" {
  depends_on = [
    module.controllers,
    module.workers,
    local_file.inventory,
    local_file.ssh_config
  ]

  provisioner "local-exec" {
    command = "${path.module}/scripts/setup-k8s.sh"
    environment = {
      LB_DNS = module.controllers.instances[0].public_ip
    }
  }

  triggers = {
    always_run = timestamp()
  }
}