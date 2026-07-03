# ingress.tf - dns module
# Creates shared ALB Ingress resources for dev and prod namespaces.

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["petclinic-${var.environment}-vpc"]
  }
}

resource "kubernetes_manifest" "ingress_dev" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "petclinic-ingress"
      namespace = "petclinic-dev"
      annotations = {
        "kubernetes.io/ingress.class"                = "alb"
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/group.name"       = "petclinic-shared"
        "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80},{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
        "alb.ingress.kubernetes.io/certificate-arn"  = aws_acm_certificate.petclinic.arn
        "alb.ingress.kubernetes.io/healthcheck-path" = "/actuator/health"
        "alb.ingress.kubernetes.io/healthcheck-port" = "8080"
      }
    }
    spec = {
      rules = [
        {
          host = "petclinic-dev.amitwebsite.online"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "api-gateway"
                    port = {
                      number = 8080
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_namespace.petclinic_dev
  ]
}

resource "kubernetes_manifest" "ingress_prod" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "petclinic-ingress"
      namespace = "petclinic-prod"
      annotations = {
        "kubernetes.io/ingress.class"                = "alb"
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/group.name"       = "petclinic-shared"
        "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80},{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
        "alb.ingress.kubernetes.io/certificate-arn"  = aws_acm_certificate.petclinic.arn
        "alb.ingress.kubernetes.io/healthcheck-path" = "/actuator/health"
        "alb.ingress.kubernetes.io/healthcheck-port" = "8080"
      }
    }
    spec = {
      rules = [
        {
          host = "petclinic.amitwebsite.online"
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "api-gateway"
                    port = {
                      number = 8080
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_namespace.petclinic_prod
  ]
}
