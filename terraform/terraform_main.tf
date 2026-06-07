# ============================================================
# PC4: Crypto Trading Pipeline - Infraestructura Completa
# ============================================================
#
# Este Terraform despliega TODA la arquitectura:
#   - Kinesis Stream (broker-PC4)
#   - DynamoDB (tabla-PC4 + storage-add-PC4)
#   - Lambda Consumer (consumer-PC4)
#   - Lambda Event Processor (event-processor-PC4)
#   - SQS DLQ (dlq-lambda-PC4)
#   - SNS Topic (crypto-trading-alerts)
#   - EventBridge Schedule (large-trade-alert)
#   - IAM Roles y Policies
#
# Uso:
#   cd terraform/
#   terraform init
#   terraform apply
#
# Para más detalles sobre el despliegue y la arquitectura,
# consultar el README.md del repositorio.
# ============================================================

terraform {
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

# ============================================================
# VARIABLES
# ============================================================

variable "aws_region" {
  default = "us-east-1"
}

variable "alert_email" {
  description = "Email para recibir alertas SNS"
  type        = string
}

variable "lab_role_arn" {
  description = "ARN del LabRole (si usas cuenta de laboratorio)"
  type        = string
  default     = ""
}

# ============================================================
# CAPA 1: INGESTA — Kinesis Stream
# ============================================================

resource "aws_kinesis_stream" "broker" {
  name             = "broker-PC4"
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
  retention_period = 24

  tags = {
    Project = "PC4"
    Layer   = "Ingesta"
  }
}

# ============================================================
# CAPA 2: ALMACENAMIENTO — DynamoDB
# ============================================================

# Tabla de trades filtrados (> $500)
resource "aws_dynamodb_table" "tabla_pc4" {
  name         = "tabla-PC4"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "symbol"
  range_key    = "exchange_ts"

  attribute {
    name = "symbol"
    type = "S"
  }

  attribute {
    name = "exchange_ts"
    type = "S"
  }

  tags = {
    Project = "PC4"
    Layer   = "Almacenamiento"
    Tipo    = "Trades-Filtrados"
  }
}

# Tabla de agregados (globales + por minuto)
resource "aws_dynamodb_table" "storage_add_pc4" {
  name         = "storage-add-PC4"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "symbol"

  attribute {
    name = "symbol"
    type = "S"
  }

  tags = {
    Project = "PC4"
    Layer   = "Almacenamiento"
    Tipo    = "Agregados"
  }
}

# ============================================================
# CAPA 2: ERRORES — SQS Dead Letter Queue
# ============================================================

resource "aws_sqs_queue" "dlq" {
  name                       = "dlq-lambda-PC4"
  message_retention_seconds  = 1209600  # 14 días
  visibility_timeout_seconds = 30

  tags = {
    Project = "PC4"
    Layer   = "Errores"
  }
}

# ============================================================
# CAPA 3: ALERTAS — SNS Topic
# ============================================================

resource "aws_sns_topic" "alerts" {
  name = "crypto-trading-alerts"

  tags = {
    Project = "PC4"
    Layer   = "Alertas"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ============================================================
# IAM — Roles y Policies
# ============================================================

# Rol para Lambda Consumer
resource "aws_iam_role" "lambda_consumer_role" {
  count = var.lab_role_arn == "" ? 1 : 0
  name  = "lambda-consumer-PC4-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_consumer_policy" {
  count = var.lab_role_arn == "" ? 1 : 0
  name  = "lambda-consumer-PC4-policy"
  role  = aws_iam_role.lambda_consumer_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:ListStreams", "kinesis:ListShards"]
        Resource = aws_kinesis_stream.broker.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = [aws_dynamodb_table.tabla_pc4.arn, aws_dynamodb_table.storage_add_pc4.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      }
    ]
  })
}

# Rol para Lambda Event Processor
resource "aws_iam_role" "lambda_event_processor_role" {
  count = var.lab_role_arn == "" ? 1 : 0
  name  = "lambda-event-processor-PC4-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_event_processor_policy" {
  count = var.lab_role_arn == "" ? 1 : 0
  name  = "lambda-event-processor-PC4-policy"
  role  = aws_iam_role.lambda_event_processor_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Scan", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.storage_add_pc4.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      }
    ]
  })
}

# ============================================================
# LAMBDA 1: Consumer (Kinesis → DynamoDB + SQS)
# ============================================================

data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/consumer.py"
  output_path = "${path.module}/consumer.zip"
}

resource "aws_lambda_function" "consumer" {
  function_name    = "consumer-PC4"
  filename         = data.archive_file.consumer_zip.output_path
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256
  handler          = "consumer.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 128

  role = var.lab_role_arn != "" ? var.lab_role_arn : aws_iam_role.lambda_consumer_role[0].arn

  tags = {
    Project = "PC4"
    Layer   = "Procesamiento"
  }
}

# Trigger: Kinesis → Lambda Consumer
resource "aws_lambda_event_source_mapping" "kinesis_to_consumer" {
  event_source_arn                   = aws_kinesis_stream.broker.arn
  function_name                      = aws_lambda_function.consumer.function_name
  enabled                            = true
  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  starting_position                  = "LATEST"
  function_response_types            = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }
}

# ============================================================
# LAMBDA 2: Event Processor (EventBridge → SNS)
# ============================================================

data "archive_file" "event_processor_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/event_processor.py"
  output_path = "${path.module}/event_processor.zip"
}

resource "aws_lambda_function" "event_processor" {
  function_name    = "event-processor-PC4"
  filename         = data.archive_file.event_processor_zip.output_path
  source_code_hash = data.archive_file.event_processor_zip.output_base64sha256
  handler          = "event_processor.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128

  role = var.lab_role_arn != "" ? var.lab_role_arn : aws_iam_role.lambda_event_processor_role[0].arn

  tags = {
    Project = "PC4"
    Layer   = "Alertas"
  }
}

# ============================================================
# EVENTBRIDGE — Schedule (cada 5 minutos)
# ============================================================

resource "aws_scheduler_schedule" "large_trade_alert" {
  name        = "large-trade-alert"
  description = "Revisa agregados cada 5 minutos y alerta si value_usd > $3.000"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(5 minutes)"

  target {
    arn      = aws_lambda_function.event_processor.arn
    role_arn = var.lab_role_arn != "" ? var.lab_role_arn : aws_iam_role.lambda_event_processor_role[0].arn
  }
}

# Permiso para que EventBridge invoque Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_processor.function_name
  principal     = "scheduler.amazonaws.com"
}

# ============================================================
# OUTPUTS
# ============================================================

output "kinesis_stream_name" {
  value = aws_kinesis_stream.broker.name
}

output "dynamodb_tabla_pc4" {
  value = aws_dynamodb_table.tabla_pc4.name
}

output "dynamodb_storage_add_pc4" {
  value = aws_dynamodb_table.storage_add_pc4.name
}

output "sqs_dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "lambda_consumer" {
  value = aws_lambda_function.consumer.function_name
}

output "lambda_event_processor" {
  value = aws_lambda_function.event_processor.function_name
}
