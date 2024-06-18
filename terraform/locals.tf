# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
locals {
  source_path   = "${path.root}/../python/src/handlers/data_ingestion_processor"
  path_include  = ["**"]
  path_exclude  = ["**/__pycache__/**"]
  files_include = setunion([for f in local.path_include : fileset(local.source_path, f)]...)
  files_exclude = setunion([for f in local.path_exclude : fileset(local.source_path, f)]...)
  files         = sort(setsubtract(local.files_include, local.files_exclude))

  dir_sha = sha1(join("", [for f in local.files : filesha1("${local.source_path}/${f}")]))

  image_tag = "latest-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  ssm_parameter_for_sagamaker = {
    PG_VECTOR_SECRET_ARN = module.aurora.cluster_master_user_secret[0].secret_arn
    PG_VECTOR_DB_NAME    = module.aurora.cluster_database_name
    PG_VECTOR_DB_HOST    = module.aurora.cluster_endpoint
    PG_VECTOR_PORT       = 5432
    CHUNK_SIZE           = 200
    CHUNK_OVERLAP        = 20
    VECTOR_DB_INDEX      = "sample-index"
    EMBEDDING_MODEL_ID   = var.embedding_model_id
    S3_BUCKET_NAME       = module.s3.s3_bucket_id
  }

  text_generation_model_arns = formatlist("arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/%s", var.text_generation_model_ids)

  vpc_endpoints = {
    s3              = "Gateway",
    bedrock-runtime = "Interface",
    secretsmanager  = "Interface",
  }
}
