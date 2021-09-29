output "rds_address" {
  value = aws_route53_record.smartview_rds.fqdn
}
