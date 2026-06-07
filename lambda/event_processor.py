import json
import boto3
from datetime import datetime
from decimal import Decimal

sns = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")

SNS_TOPIC_ARN = "arn:aws:sns:us-east-1:133657385695:trade-alert"  # ← CAMBIAR por tu ARN
TABLE_NAME = "storage-add-PC4"
LARGE_TRADE_THRESHOLD = Decimal('3000')

def lambda_handler(event, context):
    print(f"EventBridge triggered at {datetime.now()}")
    
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        # Buscar trades > $5000
        response = table.scan(
            FilterExpression="attribute_exists(value_usd) AND value_usd > :threshold",
            ExpressionAttributeValues={":threshold": LARGE_TRADE_THRESHOLD}
        )
        
        items = response.get("Items", [])
        print(f"Found {len(items)} large trades")
        
        if items:
            # Construir mensaje
            message = "🚨 CRYPTO TRADING ALERT 🚨\n\nDetectados trades grandes (>$3000):\n\n"
            for item in items[:10]:
                symbol = item.get("symbol", "N/A")
                value = item.get("total_value_usd", 0)
                trades = item.get("total_trades", 0)
                message += f"Símbolo: {symbol}\nValor: ${value:,.2f}\nTrades: {trades}\n---\n"
            
            # Enviar a SNS
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject="🚨 Crypto Alert - Large Trades Detected",
                Message=message
            )
            print("Alert sent")
        
        return {"statusCode": 200, "body": "OK"}
    
    except Exception as e:
        print(f"ERROR: {str(e)}")
        raise