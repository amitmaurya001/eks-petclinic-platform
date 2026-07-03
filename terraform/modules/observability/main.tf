# main.tf - observability module
# Creates Prometheus and Grafana resources.

resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  namespace        = "monitoring"
  create_namespace = true
  tags = {
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}