# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "this" {}

data "aws_ecr_authorization_token" "token" {}
