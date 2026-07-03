# outputs.tf - prod-k8s environment
# Exposes outputs from the DNS / k8s add-ons module.

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = module.dns.certificate_arn
}

output "acm_validation_records" {
  description = "DNS validation records for the ACM certificate (name, type, value) keyed by domain name"
  value       = module.dns.validation_records
}

output "alb_controller_role_arn" {
  description = "ARN of the IAM role used by the AWS Load Balancer Controller"
  value       = module.dns.alb_controller_role_arn
}
