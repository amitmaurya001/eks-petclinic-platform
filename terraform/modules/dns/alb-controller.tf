# alb-controller.tf - dns module
# Deploys the AWS Load Balancer Controller via IRSA and Helm.

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

data "http" "aws_load_balancer_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for the AWS Load Balancer Controller"
  policy      = data.http.aws_load_balancer_controller_policy.response_body

  tags = merge({
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.common_tags)
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "petclinic-${var.environment}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json

  tags = merge({
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.common_tags)
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.eks_cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller.arn
        }
      }
    })
  ]

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.aws_vpc.this.id
  }

  depends_on = [
    aws_iam_role_policy_attachment.aws_load_balancer_controller
  ]
}
