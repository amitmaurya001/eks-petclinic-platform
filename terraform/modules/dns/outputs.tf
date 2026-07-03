# outputs.tf - dns module
# Defines outputs for the ACM certificate and DNS validation records.

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.petclinic.arn
}

output "validation_records" {
  description = "DNS validation records for the ACM certificate (name, type, value) keyed by domain name"
  value = {
    for dvo in aws_acm_certificate.petclinic.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}

output "alb_controller_role_arn" {
  description = "ARN of the IAM role used by the AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}
