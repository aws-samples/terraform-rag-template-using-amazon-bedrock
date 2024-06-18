# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.32"
    }
  }
}
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = "dev"
      Project     = "aws-sample-bedrock-rag-template"
    }
  }
}

module "vpc" {
  #checkov:skip=CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
  source                  = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc?ref=4a2809c"
  name                    = "bedrock-rag-template"
  cidr                    = var.vpc.cidr
  private_subnets         = var.vpc.private_subnets
  public_subnets          = var.vpc.public_subnets
  map_public_ip_on_launch = false
  one_nat_gateway_per_az  = false
  enable_nat_gateway      = false
  azs                     = slice(data.aws_availability_zones.this.names, 0, 3)
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = false


  enable_flow_log                          = true
  create_flow_log_cloudwatch_iam_role      = true
  create_flow_log_cloudwatch_log_group     = true
  flow_log_cloudwatch_log_group_kms_key_id = module.kms.key_arn
}


resource "aws_security_group" "lambda_ingestion" {
  vpc_id      = module.vpc.vpc_id
  name        = "Lambda data ingestion"
  description = "SG to allow connections for Lamdba to RDS and VPC endpoints"

  egress {
    description = "Allow traffic to RDS Postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "TCP"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
  }

  egress {
    description     = "Allow HTTPS to VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "TCP"
    security_groups = [aws_security_group.vpc_endpoints.id]
    prefix_list_ids = [aws_vpc_endpoint.vpce["s3"].prefix_list_id]
  }
}


resource "aws_ssm_parameter" "parameters" {
  #checkov:skip=CKV_AWS_337: "Ensure SSM parameters are using KMS CMK"
  #checkov:skip=CKV2_AWS_34: "AWS SSM Parameter should be Encrypted"
  for_each = local.ssm_parameter_for_sagamaker
  name     = "/bedrock-rag-template/${each.key}"
  type     = "String"
  value    = each.value
}


module "lambda_ingestion" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-lambda.git?ref=9acd3227087db56abac5f78d1a660b08ee159a9c" # TODO: update

  function_name         = "data-ingestion-processor"
  description           = ""
  timeout               = 180
  tracing_mode          = "Active"
  attach_tracing_policy = true
  authorization_type    = "AWS_IAM"
  memory_size           = 2048
  kms_key_arn           = module.kms.key_arn
  publish               = true


  environment_variables = {
    PG_VECTOR_SECRET_ARN         = module.aurora.cluster_master_user_secret[0].secret_arn
    PG_VECTOR_DB_NAME            = module.aurora.cluster_database_name
    PG_VECTOR_DB_HOST            = module.aurora.cluster_endpoint
    PG_VECTOR_PORT               = 5432
    POWERTOOLS_METRICS_NAMESPACE = "GENAI"
    POWERTOOLS_SERVICE_NAME      = "data ingestion processor"
    POWERTOOLS_LOG_LEVEL         = "INFO"
    CHUNK_SIZE                   = 1000
    CHUNK_OVERLAP                = 100
    VECTOR_DB_INDEX              = "sample-index"
    EMBEDDING_MODEL_ID           = var.embedding_model_id
  }

  attach_network_policy  = true
  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.lambda_ingestion.id]

  image_uri      = data.aws_ecr_image.lambda_document_ingestion.image_uri
  create_package = false
  package_type   = "Image"

  allowed_triggers = {
    InvokeLambdaFromS3Bucket = {
      principal  = "s3.amazonaws.com"
      source_arn = module.s3.s3_bucket_arn
    }
  }



  attach_policy_json = true
  policy_json = templatefile("${path.module}/policies/data_ingestion_processor.json", {
    aurora_secret_arn = module.aurora.cluster_master_user_secret[0].secret_arn
    s3_bucket_arn     = module.s3.s3_bucket_arn
    kms_key_arn       = module.kms.key_arn
    account_id        = data.aws_caller_identity.current.id
    aws_region        = data.aws_region.current.name
    prefix            = "bedrock-rag-template"


    bedrock_model_ids = concat(
      ["arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.embedding_model_id}"],
      local.text_generation_model_arns
    )
  })

  depends_on = [null_resource.build_and_push_docker_image]


  assume_role_policy_statements = {
    sage_maker_notebook_demo = {
      effect  = "Allow",
      actions = ["sts:AssumeRole"],
      principals = {
        service_principal = {
          type        = "Service",
          identifiers = ["sagemaker.amazonaws.com", ]
        }
      }
    }
  }
}


module "ecr" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecr.git?ref=9daab07"

  repository_name                 = "bedrock-rag-template"
  repository_image_tag_mutability = "IMMUTABLE"
  repository_force_delete         = true
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 30 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}


resource "null_resource" "build_and_push_docker_image" {
  provisioner "local-exec" {
    command = <<-EOT
    aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${module.ecr.repository_url}
    docker build \
      --platform=linux/amd64 \
      -t ${module.ecr.repository_url}:${local.dir_sha} \
      ${local.source_path}
    docker push ${module.ecr.repository_url}:${local.dir_sha}
    EOT
  }

  triggers = {
    dir_sha = local.dir_sha
  }
}

data "aws_ecr_image" "lambda_document_ingestion" {
  repository_name = module.ecr.repository_name
  image_tag       = local.dir_sha
  depends_on = [
    null_resource.build_and_push_docker_image
  ]
}


module "s3" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=8a0b697"

  bucket = "bedrock-rag-template${data.aws_caller_identity.current.account_id}"

  force_destroy = true
  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = module.kms.key_arn
        sse_algorithm     = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }
  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true
  allowed_kms_key_arn                   = module.kms.key_arn


  lifecycle_rule = [
    {
      id      = "transition-to-glacier"
      enabled = true

      # Transition to Glacier after 30 days
      transitions = [
        {
          days          = 30
          storage_class = "GLACIER"
        }
      ]

      # Expire after 365 days
      expiration = {
        days = 365
      }
    }
  ]



}


resource "aws_s3_bucket_notification" "this" {
  bucket = module.s3.s3_bucket_id
  lambda_function {
    lambda_function_arn = module.lambda_ingestion.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
  }
}

module "kms" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-kms.git?ref=866950f91b3bc4411fa14d1f5c2c304145540d7f"

  description = "Bedrock RAG Template Encrytion"
  key_usage   = "ENCRYPT_DECRYPT"
  aliases     = ["aws-sample/bedrock-rag-template"]

  key_statements = [
    jsondecode(templatefile("${path.module}/policies/kms.json", {
      aws_region     = data.aws_region.current.name
      aws_account_id = data.aws_caller_identity.current.account_id
    }))
  ]
}


module "aurora" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-rds-aurora.git?ref=39146d5"

  name = "bedrock-rag-sample"

  engine              = "aurora-postgresql"
  engine_version      = "15.5"
  engine_mode         = "provisioned"
  autoscaling_enabled = true
  serverlessv2_scaling_configuration = {
    min_capacity = 1
    max_capacity = 10
  }
  instance_class = "db.serverless"
  instances = {
    one = {}
    two = {}
  }

  backtrack_window    = 259200 # 72 hours
  deletion_protection = true



  master_username                                        = "root"
  master_user_password_rotation_automatically_after_days = 7
  master_user_secret_kms_key_id                          = module.kms.key_id
  manage_master_user_password_rotation                   = true

  database_name = "bedrockRagSample"

  kms_key_id = module.kms.key_arn

  subnets                   = module.vpc.private_subnets
  skip_final_snapshot       = false
  final_snapshot_identifier = "bedrock-rag-sample-final-snapshot"

  create_db_subnet_group = true

  vpc_id = module.vpc.vpc_id
  security_group_rules = {
    ingress = {
      description = "Manage ingress to PG Vector data base"
      cidr_blocks = [module.vpc.vpc_cidr_block]
      protocol    = "tcp"
    }
  }

  storage_encrypted   = true
  apply_immediately   = true
  monitoring_interval = 10

  enabled_cloudwatch_logs_exports = ["postgresql"]
  cloudwatch_log_group_kms_key_id = module.kms.key_id

  performance_insights_enabled    = true
  performance_insights_kms_key_id = module.kms.key_arn
}


resource "aws_vpc_endpoint" "vpce" {
  for_each = local.vpc_endpoints

  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type = each.value

  route_table_ids     = each.value == "Gateway" ? concat([module.vpc.default_route_table_id], module.vpc.private_route_table_ids) : []
  private_dns_enabled = each.value == "Interface" # enable private DNS for interface endpoints
  security_group_ids  = each.value == "Interface" ? [aws_security_group.vpc_endpoints.id] : []
  subnet_ids          = each.value == "Interface" ? module.vpc.private_subnets : []

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow-only-current-account"
        Effect    = "Allow"
        Principal = "*"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.id
          }
        }
      }
    ]
  })
}


resource "aws_security_group" "vpc_endpoints" {
  #checkov:skip=CKV2_AWS_5: "Security group attached to vpc endpoints"
  vpc_id      = module.vpc.vpc_id
  name        = "vpc-endpoint"
  description = "Allow traffic from within vpc"

  ingress {
    description = "Allow HTTPS connection towards vpc endpoint"
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}


resource "aws_sagemaker_notebook_instance" "demo" {
  #checkov:skip=CKV_AWS_122: "Demo instance only"
  #checkov:skip=CKV_AWS_307: "Use will need to install dependencies"
  name          = "aws-sample-bedrock-rag-template"
  role_arn      = module.lambda_ingestion.lambda_role_arn
  instance_type = "ml.t2.medium"
  kms_key_id    = module.kms.key_arn

  subnet_id              = module.vpc.private_subnets[0]
  security_groups        = [aws_security_group.lambda_ingestion.id]
  direct_internet_access = "Enabled" # Required to download depenencies
}
