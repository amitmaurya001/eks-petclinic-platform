# main.tf - vpc module
# Creates a VPC with public subnets and Internet Gateway.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "petclinic-${var.environment}-vpc"
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[0]
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags = {
    Name                     = "petclinic-${var.environment}-public-a"
    Project                  = "petclinic"
    Environment              = var.environment
    ManagedBy                = "terraform"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[1]
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true
  tags = {
    Name                     = "petclinic-${var.environment}-public-b"
    Project                  = "petclinic"
    Environment              = var.environment
    ManagedBy                = "terraform"
    "kubernetes.io/role/elb" = "1"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "petclinic-${var.environment}-igw"
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "petclinic-${var.environment}-public-rt"
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "eks_cluster" {
  name        = "petclinic-${var.environment}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name        = "petclinic-${var.environment}-eks-cluster-sg"
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "eks_node" {
  name        = "petclinic-${var.environment}-eks-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name        = "petclinic-${var.environment}-eks-node-sg"
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "rds" {
  name        = "petclinic-${var.environment}-rds-sg"
  description = "Security group for RDS MySQL instance"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name        = "petclinic-${var.environment}-rds-sg"
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_security_group" "alb" {
  name        = "petclinic-${var.environment}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name        = "petclinic-${var.environment}-alb-sg"
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Security Group Rules
resource "aws_security_group_rule" "eks_cluster_ingress_nodes" {
  security_group_id        = aws_security_group.eks_cluster.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "eks_cluster_egress" {
  security_group_id = aws_security_group.eks_cluster.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "eks_node_ingress_cluster" {
  security_group_id        = aws_security_group.eks_node.id
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster.id
}

resource "aws_security_group_rule" "eks_node_ingress_self" {
  security_group_id = aws_security_group.eks_node.id
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
}

resource "aws_security_group_rule" "eks_node_ingress_kubelet" {
  security_group_id        = aws_security_group.eks_node.id
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
}

resource "aws_security_group_rule" "eks_node_ingress_nodeport" {
  security_group_id        = aws_security_group.eks_node.id
  type                     = "ingress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "eks_node_egress" {
  security_group_id = aws_security_group.eks_node.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "rds_ingress_nodes" {
  security_group_id        = aws_security_group.rds.id
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "rds_ingress_cluster" {
  count = var.eks_cluster_security_group_id != null ? 1 : 0

  security_group_id        = aws_security_group.rds.id
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = var.eks_cluster_security_group_id
}

resource "aws_security_group_rule" "alb_ingress_http" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_ingress_https" {
  security_group_id = aws_security_group.alb.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "alb_egress_nodeport" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "alb_egress_health" {
  security_group_id        = aws_security_group.alb.id
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
}