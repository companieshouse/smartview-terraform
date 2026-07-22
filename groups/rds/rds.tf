# ------------------------------------------------------------------------------
# RDS Security Group and rules
# ------------------------------------------------------------------------------
module "rds_security_group" {

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3.0"

  name        = "sgr-smartview-rds-001"
  description = "Security group for the smartview RDS database"
  vpc_id      = data.aws_vpc.vpc.id

  ingress_cidr_blocks = local.app_cidrs
  ingress_rules       = ["oracle-db-tcp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 5500
      to_port     = 5500
      protocol    = "tcp"
      description = "Oracle Enterprise Manager"
      cidr_blocks = join(",", local.app_cidrs)
    }
  ]

  egress_rules = ["all-all"]
}
resource "aws_security_group_rule" "admin_ingress" {

  description       = "Allow Oracle DB listener from admin prefix list"
  type              = "ingress"
  from_port         = 1521
  to_port           = 1521
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.admin.id]
  security_group_id = module.rds_security_group.this_security_group_id
}

resource "aws_security_group_rule" "admin_ingress_oem" {

  description       = "Allow Oracle Enterprise Manager from admin prefix list"
  type              = "ingress"
  from_port         = 5500
  to_port           = 5500
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.admin.id]
  security_group_id = module.rds_security_group.this_security_group_id
}

# ------------------------------------------------------------------------------
# RDS Instance
# ------------------------------------------------------------------------------
module "smartview_rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "2.23.0"

  create_db_parameter_group = true
  create_db_subnet_group    = true

  character_set_name         = "WE8MSWIN1252"
  identifier                 = "rds-${var.identifier}-${var.environment}-001"
  engine                     = "oracle-se2"
  major_engine_version       = var.major_engine_version
  engine_version             = var.engine_version
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  license_model              = var.license_model
  instance_class             = var.instance_class
  allocated_storage          = var.allocated_storage
  storage_type               = var.storage_type
  iops                       = var.iops
  multi_az                   = var.multi_az
  storage_encrypted          = true
  kms_key_id                 = data.aws_kms_key.rds.arn

  name     = upper(var.name)
  username = local.smartview_rds_data["admin-username"]
  password = local.smartview_rds_data["admin-password"]
  port     = "1521"

  deletion_protection       = true
  maintenance_window        = var.rds_maintenance_window
  backup_window             = var.rds_backup_window
  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.identifier}-final-deletion-snapshot"

  # Enhanced Monitoring
  monitoring_interval             = "30"
  monitoring_role_arn             = data.aws_iam_role.rds_enhanced_monitoring.arn
  enabled_cloudwatch_logs_exports = var.rds_log_exports

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = data.aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  ca_cert_identifier = "rds-ca-rsa2048-g1"

  # RDS Security Group
  vpc_security_group_ids = [
    module.rds_security_group.this_security_group_id,
    data.aws_security_group.rds_shared.id
  ]

  # DB subnet group
  subnet_ids = data.aws_subnet_ids.data.ids

  # DB Parameter group
  family = "oracle-se2-${var.major_engine_version}"

  parameters = var.parameter_group_settings

  options = concat([
    {
      option_name                    = "OEM"
      port                           = "5500"
      vpc_security_group_memberships = [module.rds_security_group.this_security_group_id]
    }
  ], var.option_group_settings)

  timeouts = {
    "create" : "80m",
    "delete" : "80m",
    "update" : "80m"
  }

  tags = merge(
    local.default_tags,
    map(
      "ServiceTeam", "${upper(var.identifier)}-DBA-Support"
    )
  )
}

module "rds_start_stop_schedule" {
  source = "git@github.com:companieshouse/terraform-modules//aws/rds_start_stop_schedule?ref=tags/1.0.131"

  rds_schedule_enable = var.rds_schedule_enable

  rds_instance_id     = module.smartview_rds.this_db_instance_id
  rds_start_schedule  = var.rds_start_schedule
  rds_stop_schedule   = var.rds_stop_schedule
}

module "rds_cloudwatch_alarms" {
  source = "git@github.com:companieshouse/terraform-modules//aws/oracledb_cloudwatch_alarms?ref=tags/1.0.236"

  db_instance_id         = module.smartview_rds.this_db_instance_id
  db_instance_shortname  = upper(var.name)
  alarm_actions_enabled  = var.alarm_actions_enabled
  alarm_name_prefix      = "Oracle RDS"
  alarm_topic_name       = var.alarm_topic_name
  alarm_topic_name_ooh   = var.alarm_topic_name_ooh
}
