locals {
  portal_names = sort(keys(var.instance_types))

  common_tags = {
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Project            = "ocean-across-payroll"
    DataClassification = "Confidential"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

module "networking" {
  source = "./modules/networking"

  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  common_tags              = local.common_tags
}

module "security" {
  source = "./modules/security"

  environment              = var.environment
  vpc_id                   = module.networking.vpc_id
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  application_subnet_ids   = module.networking.application_private_subnet_ids
  database_subnet_ids      = module.networking.database_private_subnet_ids
  application_port         = var.application_port
  https_ingress_cidrs      = var.https_ingress_cidrs
  ssh_allowed_cidr         = var.ssh_allowed_cidr
  common_tags              = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  environment           = var.environment
  aws_region            = var.aws_region
  portals               = local.portal_names
  documents_bucket_name = module.storage.bucket_name
  documents_bucket_arn  = module.storage.bucket_arn
  portal_prefixes       = module.storage.portal_prefixes
  common_tags           = local.common_tags
}

module "compute" {
  source = "./modules/compute"

  environment            = var.environment
  instance_types         = var.instance_types
  subnet_ids             = module.networking.application_private_subnet_ids
  security_group_ids     = module.security.portal_security_group_ids
  instance_profile_names = module.iam.portal_instance_profile_names
  ami_id                 = var.ec2_ami_id
  owner                  = var.resource_owner
  common_tags            = local.common_tags
}

module "database" {
  source = "./modules/database"

  environment           = var.environment
  db_name               = var.db_name
  db_instance_class     = var.db_instance_class
  engine_version        = var.db_engine_version
  master_username       = var.db_master_username
  subnet_ids            = module.networking.database_private_subnet_ids
  security_group_id     = module.security.rds_security_group_id
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.rds_deletion_protection
  common_tags           = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  environment                       = var.environment
  noncurrent_version_retention_days = var.s3_noncurrent_version_retention_days
  common_tags                       = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  environment               = var.environment
  portals                   = local.portal_names
  portal_instance_ids       = module.compute.instance_ids
  rds_instance_id           = module.database.instance_id
  log_retention_days        = var.log_retention_days
  ec2_cpu_threshold_percent = var.ec2_cpu_threshold_percent
  rds_connection_threshold  = var.rds_connection_threshold
  alert_email               = var.alert_email
  sns_kms_key_arn           = var.sns_kms_key_arn
  common_tags               = local.common_tags
}
