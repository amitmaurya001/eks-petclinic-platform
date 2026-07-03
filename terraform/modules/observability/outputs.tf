# outputs.tf - observability module
# Defines outputs for the Observability module.

output "prometheus_service_name" {
  description = "Name of the Prometheus service"
  value       = helm_release.prometheus.name
}