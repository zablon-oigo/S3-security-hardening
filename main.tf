provider "aws" {
  region = "${var.region}"
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
}
resource "random_pet" "bucket_name" {
  length    = 2
  separator = "-"
}
resource "aws_s3_bucket" "bucket" {
  bucket = "${var.service_name}-${random_pet.bucket_name.id}"

  tags = {
    Service     = "${var.service_name}"
    Environment = "${var.environment}"
    Name        = "${var.service_name}-${var.environment}-s3-bucket"
    Terraform   = "true"
  }
}
resource "aws_s3_bucket_ownership_controls" "bucket_ownership" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
data "aws_iam_policy_document" "lambda_role_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
  
}
resource "aws_iam_role" "lambda_execution_role"{
  name="${var.service_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_role_trust_policy.json
}

resource "aws_iam_role_policy_attachment" "service_lambda_role_basic_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
data "aws_iam_policy_document" "s3_access_policy_document" {
  statement {
    actions   = ["s3:putObject", "s3:getObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]
  }
}
resource "aws_iam_role_policy" "lambda_s3_access_policy" {
  name   = "iam_for_lambda_policy"
  role   = aws_iam_role.service_lambda_execution_role.id
  policy = data.aws_iam_policy_document.s3_access_policy_document.json
}
resource "aws_lambda_function" "lambda_function" {
  function_name    = "${var.service_name}-function"
  filename         = data.archive_file.lambda_zip.output_path
  role             = aws_iam_role.service_lambda_execution_role.arn
  vpc_config {
    subnet_ids         = var.private_subnet_ids 
    security_group_ids = [aws_security_group.service_lambda_sg.id]
  }
environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.bucket.bucket
    }
  }
tags = {
    "Service"     = var.service_name
    "Environment" = var.environment
    "Name"        = "${var.service_name}-service-lambda-function"
    "Terraform"   = "true"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "sse_config" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.kms_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}
data "aws_iam_policy_document" "s3_endpoint_policy" {
  statement {
    actions   = ["s3:putObject", "s3:getObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.service_lambda_execution_role.arn] # only allow access to this endpoint from the Lambda function
    }
  }
}