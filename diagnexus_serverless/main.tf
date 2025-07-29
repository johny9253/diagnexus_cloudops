terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

#####################
# SNS Topic (Create)
#####################

resource "aws_sns_topic" "diagnexus_topic" {
  name = "diagnexus_topic"
}

#####################
# IAM Role & Policy #
#####################

resource "aws_iam_role" "lambda_exec_role" {
  name = "process_patient_report_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_policy_for_process_patient_report"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::diagnexus-medical-reports",
          "arn:aws:s3:::diagnexus-medical-reports/*",
          "arn:aws:s3:::diagnexus-deployement-pkg",
          "arn:aws:s3:::diagnexus-deployement-pkg/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.diagnexus_topic.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

########################
# Lambda Configuration #
########################

resource "aws_lambda_function" "process_patient_report" {
  function_name = "process-patient-report-lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "dist/process-parsed-report.handler"
  runtime       = "nodejs22.x"
  memory_size   = 256
  timeout       = 900

  s3_bucket = "diagnexus-deployement-pkg"
  s3_key    = "lambda.zip"

  environment {
    variables = {
      NODE_ENV = "production"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_exec_policy_attach]
}

##########################
# Lambda S3 Permissions  #
##########################

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_patient_report.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::diagnexus-medical-reports"
}

resource "aws_s3_bucket_notification" "s3_trigger_lambda" {
  bucket = "diagnexus-medical-reports"

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_patient_report.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

#############################
# CloudWatch Logs for Lambda
#############################

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/process-patient-report-lambda"
  retention_in_days = 30
}

#############################
# SNS Failure Notification
#############################

resource "aws_lambda_function_event_invoke_config" "lambda_failure_config" {
  function_name          = aws_lambda_function.process_patient_report.function_name
  maximum_retry_attempts = 2

  destination_config {
    on_failure {
      destination = aws_sns_topic.diagnexus_topic.arn
    }
  }

  depends_on = [aws_lambda_function.process_patient_report]
}

##########################
# SNS Email Subscription
##########################

resource "aws_sns_topic_subscription" "failure_email" {
  topic_arn = aws_sns_topic.diagnexus_topic.arn
  protocol  = "email"
  endpoint  = "deepaksingh9253@gmail.com"
}
