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

# Tabla 1: Trades filtrados (valor > 1000 o ventas agresivas)
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
    Description = "Filtered trades (high value or aggressive sells)"
    Environment = var.environment
  }
}

# Tabla 2: Agregados por símbolo (global + por minuto)
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
  name                      = "dlq-lambda-PC4"
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name        = "dlq-lambda-PC4"
    Description = "Dead Letter Queue for Lambda errors"
    Environment = var.environment
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# IAM ROLE FOR LAMBDA
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "lambda_role" {
  name = "lambda-consumer-PC4-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "lambda-consumer-PC4-role"
    Environment = var.environment
  }
}

# Policy: Kinesis read access
resource "aws_iam_role_policy" "lambda_kinesis_policy" {
  name = "lambda-kinesis-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.broker.arn
      }
    ]
  })
}

# Policy: DynamoDB write access
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = [
          aws_dynamodb_table.tabla_pc4.arn,
          aws_dynamodb_table.storage_add_pc4.arn
        ]
      }
    ]
  })
}

# Policy: SQS send access (for error queue)
resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "lambda-sqs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.dlq_lambda_pc4.arn
      }
    ]
  })
}

# Policy: CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ══════════════════════════════════════════════════════════════════════════════
# LAMBDA FUNCTION (placeholder - deploy manually or via ZIP)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_function" "consumer_pc4" {
  filename      = "lambda_placeholder.zip"
  function_name = "consumer-PC4"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  environment {
    variables = {
      KINESIS_STREAM_NAME = aws_kinesis_stream.broker.name
      DLQ_QUEUE_URL       = aws_sqs_queue.dlq_lambda_pc4.url
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_kinesis_policy,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_iam_role_policy.lambda_sqs_policy
  ]

  tags = {
    Name        = "consumer-PC4"
    Environment = var.environment
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# EVENT SOURCE MAPPING (Kinesis → Lambda)
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_lambda_event_source_mapping" "kinesis_to_lambda" {
  event_source_arn  = aws_kinesis_stream.broker.arn
  function_name     = aws_lambda_function.consumer_pc4.arn
  enabled           = true
  batch_size        = 100
  starting_position = "LATEST"
  maximum_batching_window_in_seconds = 5

  function_response_types = ["ReportBatchItemFailures"]

  # Send failed batches to DLQ
  on_failure {
    destination_arn = aws_sqs_queue.dlq_lambda_pc4.arn
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
  value       = aws_iam_role.lambda_role.arn
}
