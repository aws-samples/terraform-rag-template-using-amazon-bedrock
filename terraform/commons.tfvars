# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
vpc = {
  private_subnets    = ["10.1.3.0/24", "10.1.4.0/24"]
  public_subnets     = ["10.1.1.0/24", "10.1.2.0/24"]
  enable_nat_gateway = true
  cidr               = "10.1.0.0/16"
}
embedding_model_id = "amazon.titan-embed-text-v2:0"
text_generation_model_ids = [
  "anthropic.claude-3-sonnet-20240229-v1:0"
]
region = "us-east-1"
