data "aws_availability_zones" "available" {}
data "aws_route53_zone" "zone" {
  name = var.route53_hosted_zone_name
}
