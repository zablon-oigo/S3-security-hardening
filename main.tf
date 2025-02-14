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
resource "aws_kms_key" "kms_key" {
  description             = "KMS key for ${var.service_name} in the ${var.environment} environment"
  deletion_window_in_days = 7
  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "${var.service_name}-${var.environment}-key-policy",
     Statement = concat([
      {
        Sid    = "Allow administration of the key",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" 
        },
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key",
        Effect = "Allow",
        Principal = {
          AWS = "${aws_iam_role.service_lambda_execution_role.arn}" # allow the lambda execution role to use the key but not administer it
        },
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:CreateGrant"]
        Resource = "*"
      }]
    )
  })

  tags = {
    Service     = var.service_name
    Environment = var.environment
    Name        = "${var.service_name}-kms-key"
    Terraform   = "true"
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
      values   = [aws_iam_role.service_lambda_execution_role.arn]
    }
  }
}
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}