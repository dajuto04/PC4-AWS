# Crypto Trading Pipeline - Terraform Infrastructure

Automáticamente despliega toda la arquitectura en AWS usando Terraform.

## 📋 Estructura

```
.
├── main.tf              # Configuración principal (Kinesis, DynamoDB, Lambda, SQS)
├── terraform.tfvars     # Variables (región, ambiente, nombres)
├── producer.py          # Script que envía trades desde Coinbase
├── consumer.py          # Código Lambda (debe uploadarse manualmente)
└── README.md            # Este archivo
```

## 🚀 Cómo usar

### 1. Instalar Terraform

```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

### 2. Configurar credenciales AWS

```bash
aws configure
# Ingresa tu Access Key ID y Secret Access Key
```

O usando variables de entorno:

```bash
export AWS_ACCESS_KEY_ID="tu_access_key"
export AWS_SECRET_ACCESS_KEY="tu_secret_key"
export AWS_DEFAULT_REGION="us-east-1"
```

### 3. Inicializar Terraform

```bash
cd terraform/
terraform init
```

### 4. Ver qué se va a crear

```bash
terraform plan
```

Te mostrará todos los recursos que se crearán. Revisa que todo esté correcto.

### 5. Desplegar la infraestructura

```bash
terraform apply
```

Confirma escribiendo `yes` cuando lo pida.

**Espera ~2 minutos** a que se creen todos los recursos.

### 6. Obtener outputs

```bash
terraform output
```

Te muestra:
- Nombre del stream de Kinesis
- Nombres de las tablas DynamoDB
- URL de la cola SQS
- Nombre de la función Lambda

## 🔧 Personalizar

Edita `terraform.tfvars`:

```hcl
aws_region   = "us-east-1"    # Cambia si quieres otra región
environment  = "prod"         # dev, test, prod
project_name = "crypto"       # Prefijo para los nombres
```

## 📤 Desplegar el código Lambda

Terraform crea la función Lambda pero necesita el código. Opciones:

### Opción A: Upload manual desde consola AWS

1. Ve a Lambda → consumer-PC4
2. Botón "Upload from" → ".zip file"
3. Sube el código de `consumer.py`

### Opción B: Automatizar con Terraform (avanzado)

```hcl
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../consumer.py"
  output_path = "/tmp/lambda_function.zip"
}

resource "aws_lambda_function" "consumer_pc4" {
  filename = data.archive_file.lambda_zip.output_path
  # ... resto del código
}
```

## 🗑️ Destruir la infraestructura

Si quieres eliminar todo (CUIDADO - se pierden los datos):

```bash
terraform destroy
```

Confirma escribiendo `yes`.

## 📊 Monitorear

Después del deploy:

1. **Kinesis**: AWS Console → Kinesis → broker-PC4 → "Data viewer"
2. **DynamoDB**: AWS Console → DynamoDB → Explore tables
3. **Lambda**: CloudWatch → Log groups → /aws/lambda/consumer-PC4
4. **SQS**: AWS Console → SQS → dlq-lambda-PC4

## 🚨 Troubleshooting

**Error: "Error creating Kinesis stream"**
- Verifica credenciales AWS
- Revisa que la región es válida

**Error: "State locked"**
```bash
terraform force-unlock [LOCK_ID]
```

**Quiero cambiar algo**
1. Edita `main.tf`
2. Ejecuta `terraform plan`
3. Ejecuta `terraform apply`

## 📝 Notas

- Terraform mantiene estado en `terraform.tfstate` — **NO lo borres** (contiene la historia de lo creado)
- Para colaborar en equipo, almacena el state en S3 (terraform backend)
- PAY_PER_REQUEST en DynamoDB = pagas solo por lo que usas (ideal para dev/test)

## 🔐 Permisos IAM (para compartir con compañeros)

Si quieres dar acceso a compañeros solo para ver:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:ListShards",
        "dynamodb:Scan",
        "dynamodb:Query",
        "sqs:ReceiveMessage",
        "lambda:GetFunction",
        "cloudwatch:GetMetricStatistics"
      ],
      "Resource": "*"
    }
  ]
}
```

---

¿Preguntas? Revisa los logs de CloudWatch o contacta al equipo de infraestructura.
