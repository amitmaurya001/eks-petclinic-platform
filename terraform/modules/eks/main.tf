# main.tf - eks module
# Creates an EKS cluster with managed node group and OIDC provider.

locals {
  # Normalize cluster name once for all resources.
  cluster_name = coalesce(var.cluster_name, "petclinic-${var.environment}")
}

# Cluster IAM Role
resource "aws_iam_role" "cluster_role" {
  name = "${local.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# Attach EKS Cluster Policy to the role
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

locals {
  # Define admin users who should have system:masters access
  admin_users = []
  # Note: Cluster creator (current IAM user) gets admin permissions automatically via bootstrap_cluster_creator_admin_permissions = true
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster_role.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.cluster_sg_id]
  }

  # Enable cluster logging
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Public API endpoint
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true # Use AWS native permissions for cluster creator
  }

  # Enable encryption at rest for Kubernetes secrets
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  # Kubernetes network configuration
  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"

    elastic_load_balancing {
      enabled = false
    }
  }

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  depends_on = [aws_iam_role_policy_attachment.cluster_policy] # Wait for IAM policy attachment to finish replicating globally
}

# Create access entries for administrators
resource "aws_eks_access_entry" "admin_access" {
  for_each          = toset(local.admin_users)
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = each.value
  kubernetes_groups = ["cluster-admin"]
  type              = "STANDARD"

  # Prevent conflicts by ensuring this only tries to create if it doesn't exist
  lifecycle {
    prevent_destroy       = false
    create_before_destroy = true
  }
}

// REMOVED: cluster_creator access entry is now redundant with bootstrap_cluster_creator_admin_permissions = true
// AWS EKS 1.33+ automatically grants cluster creator admin permissions natively

# Associate access entries with cluster admin policy
resource "aws_eks_access_policy_association" "admin_access" {
  for_each      = toset(local.admin_users)
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = each.value

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.admin_access
  ]

  # Prevent destroy/conflicts
  lifecycle {
    prevent_destroy       = false
    create_before_destroy = true
    ignore_changes        = [principal_arn] # Don't recreate if principal changes
  }
}

// REMOVED: cluster_creator policy association is now redundant with bootstrap_cluster_creator_admin_permissions = true
// AWS EKS 1.33+ automatically associates policy for cluster creator

# OIDC provider for IRSA
resource "aws_iam_openid_connect_provider" "cluster_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_certificate.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# Get certificate for OIDC provider
data "tls_certificate" "eks_certificate" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Node IAM Role
resource "aws_iam_role" "node_role" {
  name = "${local.cluster_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# Node IAM Policy attachments
resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EKS Managed Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type
  disk_size      = var.node_disk_size

  # Labels and taints
  labels = {
    environment = var.environment
  }

  # Tags for cost allocation
  tags = merge({
    Project                                       = var.project
    Environment                                   = var.environment
    ManagedBy                                     = "terraform"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }, var.tags)

  # Wait for IAM policy attachments to finish replicating globally
  # (VPC CNI addon already waits for nodes via its own depends_on)
  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.ecr_readonly
  ]
}

# EKS Add-ons - CoreDNS
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  # Let EKS pick the matching version for your cluster automatically
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = null # No IRSA needed

  # FIX: Force CoreDNS to wait until your node group is fully ready
  depends_on = [
    aws_eks_node_group.main
  ]
}

# EKS Add-ons - kube-proxy
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  # Let EKS pick the matching version for your cluster automatically
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = null # No IRSA needed

  # FIX: Force kube-proxy to wait until your node group is fully ready
  depends_on = [
    aws_eks_node_group.main
  ]
}

# EKS Add-ons - VPC CNI
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  # Let EKS pick the matching version for your cluster automatically
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = null # No IRSA needed

  # FIX: Force VPC CNI to wait until your node group is fully ready
  depends_on = [
    aws_eks_node_group.main
  ]
}

# EKS Add-ons - EBS CSI Driver (requires IRSA)
resource "aws_iam_role" "ebs_csi_role" {
  name = "${local.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${aws_iam_openid_connect_provider.cluster_oidc.url}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${aws_iam_openid_connect_provider.cluster_oidc.url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${aws_iam_openid_connect_provider.cluster_oidc.url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"
  # Let EKS pick the matching version for your cluster automatically
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.ebs_csi_role.arn

  # FIX: Force EBS CSI to wait until your node group is fully ready
  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}

# KMS Key for EKS encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for ${local.cluster_name} EKS cluster encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.eks_kms_key_policy.json

  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Name        = "${local.cluster_name}-eks-key"
  }, var.tags)
}

# KMS key policy for EKS encryption
data "aws_iam_policy_document" "eks_kms_key_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow EKS service to use the key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Allow EKS IAM role to use the key"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.cluster_role.arn]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
  }
}

# Get current AWS account ID and partition
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
