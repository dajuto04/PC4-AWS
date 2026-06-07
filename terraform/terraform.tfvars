# ============================================================
# PC4: Variables de Configuración
# ============================================================
# Modificar estos valores según tu entorno.
# Para más detalles sobre el despliegue, consultar el README.md
# ============================================================

aws_region = "us-east-1"

# Email para recibir alertas SNS (CAMBIAR por tu email real)
alert_email = "tu-email@example.com"

# Si usas cuenta de laboratorio con LabRole, poner el ARN aquí.
# Si no, dejarlo vacío "" y Terraform creará los roles automáticamente.
# Ejemplo: "arn:aws:iam::133657385695:role/LabRole"
lab_role_arn = "arn:aws:iam::133657385695:role/LabRole"
