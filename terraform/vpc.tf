locals {
  cidr_block      = "10.0.0.0/16"
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]
  azs             = ["us-east-1a", "us-east-1b"]
}

resource "aws_vpc" "eks_vpc" {
  cidr_block = local.cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    "Name" = "eks-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(local.public_subnets)
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    "Name" = "public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count                   = length(local.private_subnets)
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = local.private_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    "Name" = "private-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    "Name" = "eks-igw"
  }
}

resource "aws_eip" "nat_eip" {
  count = length(local.private_subnets)
  vpc   = true

  tags = {
    "Name" = "nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  count         = length(local.private_subnets)
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id

  tags = {
    "Name" = "nat-gateway-${count.index}"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    "Name" = "public-route-table"
  }
}

resource "aws_route_table" "private_route_table" {
  count  = length(local.private_subnets)
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
  }

  tags = {
    "Name" = "private-route-table"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count          = length(local.public_subnets)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  count          = length(local.private_subnets)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "eks_cluster_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}


resource "aws_security_group" "eks_worker_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.eks_vpc.cidr_block]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-worker-sg"
  }
}