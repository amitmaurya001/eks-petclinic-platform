# outputs-alb.tf - dns module
# Additional outputs for the shared ALB Ingress.

output "alb_dns_reminder" {
  description = "kubectl command to retrieve the shared ALB hostname"
  value       = "Run: kubectl get ingress petclinic-ingress -n petclinic-dev -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
