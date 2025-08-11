# VPC
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "k8s-the-hard-way-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "k8s_igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = merge(var.tags, {
    Name = "k8s-the-hard-way-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "k8s-public-subnet-${count.index + 1}"
    Type = "public"
  })
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "k8s-private-subnet-${count.index + 1}"
    Type = "private"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_eips" {
  count = length(var.public_subnet_cidrs)

  domain = "vpc"
  depends_on = [aws_internet_gateway.k8s_igw]

  tags = merge(var.tags, {
    Name = "k8s-nat-eip-${count.index + 1}"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "nat_gateways" {
  count = length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  depends_on = [aws_internet_gateway.k8s_igw]

  tags = merge(var.tags, {
    Name = "k8s-nat-gateway-${count.index + 1}"
  })
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s_igw.id
  }

  tags = merge(var.tags, {
    Name = "k8s-public-rt"
  })
}

# Private Route Tables
resource "aws_route_table" "private_rts" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateways[count.index].id
  }

  tags = merge(var.tags, {
    Name = "k8s-private-rt-${count.index + 1}"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public_rta" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Associate private subnets with private route tables
resource "aws_route_table_association" "private_rta" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rts[count.index].id
}