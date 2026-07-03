# namespaces.tf - dns module
# Ensures the petclinic dev and prod namespaces exist before Ingress resources are created.

resource "kubernetes_namespace" "petclinic_dev" {
  metadata {
    name = "petclinic-dev"
    labels = {
      "app.kubernetes.io/name"       = "petclinic-dev"
      "app.kubernetes.io/part-of"    = "petclinic"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "petclinic_prod" {
  metadata {
    name = "petclinic-prod"
    labels = {
      "app.kubernetes.io/name"       = "petclinic-prod"
      "app.kubernetes.io/part-of"    = "petclinic"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}
