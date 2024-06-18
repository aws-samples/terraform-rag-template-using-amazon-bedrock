# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
variable "vpc" {
  type = object({
    private_subnets    = list(string)
    public_subnets     = list(string)
    enable_nat_gateway = bool
    cidr               = string
  })
}

variable "region" {
  description = "AWS region to use for deployment"
  type        = string
}

variable "embedding_model_id" {
  description = "Model id of the Amazon Bedrock embedding to use for data ingestion"
  type        = string
}

variable "text_generation_model_ids" {
  description = "Model ids of the Amazon Bedrock text generation model to use in the retrieval chain"
  type        = list(string)
}
