terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ══════════════════════════════════════════════════════════════════════════════
# VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "crypto-pipeline"
}

# ══════════════════════════════════════════════════════════════════════════════
# DATA SOURCE (Para usar el rol existente de AWS Academy)
# ══════════════════════════════════════════════════════════════════════════════

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# ══════════════════════════════════════════════════════════════════════════════
# KINESIS STREAM
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_kinesis_stream" "broker" {
  name             = "broker-PC4"
  retention_period = 24

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = {
    Name        = "broker-PC4"
    Environment = var.environment
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# DYNAMODB TABLES
# ══════════════════════════════════════════════════════════════════════════════

# Tabla 1: Trades filtrados (Corregido el Tag sin paréntesis)
resource "aws_dynamodb_table" "tabla_pc4" {
  name           = "tabla-PC4"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "symbol"
  range_key      = "exchange_ts"

  attribute {
    name = "symbol"
    type = "S"
  }

  attribute {
    name = "exchange_ts"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = false
  }

  tags = {
    Name        = "tabla-PC4"
    Description = "Filtered trades - high value or aggressive sells"
    Environment = var.environment
  }
}

# Tabla 2: Agregados por símbolo
resource "aws_dynamodb_table" "storage_add_pc4" {
  name           = "storage-add-PC4"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "symbol"

  attribute {
    name = "symbol"
    type = "S"
  }

  tags = {
    Name        = "storage-add-PC4"
    Description = "Aggregated trades by symbol and time window"
    Environment = var.environment
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# SQS QUEUE (Dead Letter Queue)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_sqs_queue" "dlq_lambda_pc4" {
  message_retention_seconds = 1209600  # 14 days
  name                      = "dlq-lambda-PC4"

  tags = {
    Name        = "dlq-lambda-PC4"
    Description = "Dead Letter Queue for Lambda errors"
    Environment = var.environment
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# LAMBDA FUNCTION
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_function" "consumer_pc4" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "consumer-PC4"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      KINESIS_STREAM_NAME = aws_kinesis_stream.broker.name
      DLQ_QUEUE_URL       = aws_sqs_queue.dlq_lambda_pc4.url
    }
  }

  tags = {
    Name        = "consumer-PC4"
    Environment = var.environment
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# EVENT SOURCE MAPPING (Kinesis → Lambda)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_event_source_mapping" "kinesis_to_lambda" {
  event_source_arn                   = aws_kinesis_stream.broker.arn
  function_name                      = aws_lambda_function.consumer_pc4.arn
  enabled                            = true
  batch_size                         = 100
  starting_position                  = "LATEST"
  maximum_batching_window_in_seconds = 5

  function_response_types = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq_lambda_pc4.arn
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ══════════════════════════════════════════════════════════════════════════════

output "kinesis_stream_name" {
  description = "Kinesis stream name"
  value       = aws_kinesis_stream.broker.name
}

output "kinesis_stream_arn" {
  description = "Kinesis stream ARN"
  value       = aws_kinesis_stream.broker.arn
}

output "dynamodb_tabla_pc4_name" {
  description = "DynamoDB table for filtered trades"
  value       = aws_dynamodb_table.tabla_pc4.name
}

output "dynamodb_storage_add_pc4_name" {
  description = "DynamoDB table for aggregates"
  value       = aws_dynamodb_table.storage_add_pc4.name
}

output "sqs_dlq_url" {
  description = "SQS Dead Letter Queue URL"
  value       = aws_sqs_queue.dlq_lambda_pc4.url
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.consumer_pc4.function_name
}

output "lambda_role_arn" {
  description = "IAM role for Lambda"
  value       = data.aws_iam_role.lab_role.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/practica_consumer_kinesis.py"
  output_path = "${path.module}/lambda_consumer.zip"
}