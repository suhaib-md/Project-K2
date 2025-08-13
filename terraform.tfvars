# AWS Configuration
aws_region = "us-west-2"

# Network Configuration
vpc_cidr             = "10.240.0.0/16"
availability_zones   = ["us-west-2a", "us-west-2b", "us-west-2c"]
public_subnet_cidrs  = ["10.240.0.0/24", "10.240.1.0/24", "10.240.2.0/24"]
private_subnet_cidrs = ["10.240.10.0/24", "10.240.11.0/24", "10.240.12.0/24"]

# Instance Configuration - Using smaller instances and fewer nodes
controller_instance_type = "t3.micro"  # 2 vCPUs -> 1 vCPU
worker_instance_type     = "t3.micro"  # 2 vCPUs -> 1 vCPU

# Common Tags
common_tags = {
  Project     = "kubernetes-the-hard-way"
  Environment = "learning"
  ManagedBy   = "terraform"
  Owner       = "suhaib"
}