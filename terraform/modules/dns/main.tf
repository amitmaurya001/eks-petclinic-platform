# main.tf - dns module
# Creates an ACM certificate only. DNS validation records are output for manual
# entry in Cloudflare (Route 53 is not used in this project).

resource "aws_acm_certificate" "petclinic" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = merge({
    Project     = "petclinic"
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)

  lifecycle {
    create_before_destroy = true
  }
}
