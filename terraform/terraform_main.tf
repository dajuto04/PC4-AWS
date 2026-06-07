# ============================================================
# PC4: Crypto Trading Pipeline - Infraestructura Completa
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

# ============================================================
# DATA SOURCE (Para usar el rol existente de AWS Academy)
# ============================================================

data "aws_iam_role" "lab_role" {
  name = "LabRole"
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
  role             = data.aws_iam_role.lab_role.arn # Usando LabRole directo

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
  role             = data.aws_iam_role.lab_role.arn # Usando LabRole directo

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
    role_arn = data.aws_iam_role.lab_role.arn # Usando LabRole directo
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