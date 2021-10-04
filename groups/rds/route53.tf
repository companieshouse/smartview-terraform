resource "aws_route53_record" "smartview_rds" {
  zone_id = data.aws_route53_zone.private_zone.zone_id
  name    = "${var.name}db"
  type    = "CNAME"
  ttl     = "300"
  records = [module.smartview_rds.this_db_instance_address]
}
