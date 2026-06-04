"""
Consumer Lambda: Kinesis → DynamoDB + SQS (para errores críticos)
Si falla un trade individual, se captura y continúa.
Si hay error crítico (DynamoDB), la Lambda falla y el batch va al SQS (DLQ).
"""

import json
import boto3
import base64
from datetime import datetime
from decimal import Decimal
import random

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

table = dynamodb.Table("tabla-PC4")
table_add = dynamodb.Table("storage-add-PC4")

SQS_ERROR_QUEUE = "https://sqs.us-east-1.amazonaws.com/133657385695/dlq-lambda-PC4"

TRADE_VALUE_THRESHOLD = 500.0
ERROR_PROBABILITY = 0.2  # 10% de probabilidad de error simulado


def get_minute_window(timestamp_str):
    dt = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))
    return dt.strftime("%Y-%m-%d %H:%M")


def send_to_error_queue(trade, error_msg):
    """Envía un trade con error a la cola SQS."""
    try:
        sqs.send_message(
            QueueUrl=SQS_ERROR_QUEUE,
            MessageBody=json.dumps({
                "trade_id": str(trade.get("trade_id")),
                "symbol": trade.get("symbol"),
                "error": error_msg,
                "timestamp": datetime.now().isoformat(),
                "trade_data": str(trade)
            })
        )
    except Exception as e:
        print(f"[CRITICAL] No se pudo enviar error a SQS: {str(e)}")


def lambda_handler(event, context):
    print(f"Recibidos {len(event['Records'])} registros de Kinesis")
    processed = 0
    failed = 0

    for record in event["Records"]:
        try:
            payload = base64.b64decode(record["kinesis"]["data"])
            trade = json.loads(payload, parse_float=Decimal)
            print(f"Trade: {trade}")

            # ── Simula error aleatorio en un trade ──────────────
            if random.random() < ERROR_PROBABILITY:
                error_msg = f"Error simulado en trade {trade.get('trade_id')}"
                print(f"[ERROR] {error_msg}")
                send_to_error_queue(trade, error_msg)
                failed += 1
                continue  # Continúa con el siguiente trade

            # ── 1. Trades filtrados ────────────────────────────
            is_large = float(trade["trade_value_usd"]) > TRADE_VALUE_THRESHOLD
            

            if is_large:
                item = {
                    "symbol": trade["symbol"],
                    "exchange_ts": str(trade["exchange_ts"]),
                    "trade_id": str(trade["trade_id"]),
                    "price": trade["price"],
                    "quantity": trade["quantity"],
                    "trade_value_usd": trade["trade_value_usd"],
                    "side": trade["side"],
                    "ingestion_ts": str(trade["ingestion_ts"]),
                }
                table.put_item(Item=item)

            # ── 2. Agregados globales ──────────────────────────
            timestamp = datetime.strftime(datetime.now(), "%Y-%m-%d %H:%M:%S")
            qty = Decimal(str(trade["quantity"]))

            table_add.update_item(
                Key={"symbol": trade["symbol"]},
                UpdateExpression="""
                    SET total_trades    = if_not_exists(total_trades, :zero) + :inc,
                        qty_bought      = if_not_exists(qty_bought, :zero) + :qty_buy,
                        qty_sold        = if_not_exists(qty_sold, :zero) + :qty_sell,
                        total_value_usd = if_not_exists(total_value_usd, :zero) + :val,
                        buy_count       = if_not_exists(buy_count, :zero) + :buy,
                        sell_count      = if_not_exists(sell_count, :zero) + :sell,
                        last_price      = :price,
                        last_updated    = :ts
                """,
                ExpressionAttributeValues={
                    ":inc": Decimal(1),
                    ":zero": Decimal(0),
                    ":qty_buy": qty if trade["side"] == "BUY" else Decimal(0),
                    ":qty_sell": qty if trade["side"] == "SELL" else Decimal(0),
                    ":val": Decimal(str(trade["trade_value_usd"])),
                    ":buy": Decimal(1) if trade["side"] == "BUY" else Decimal(0),
                    ":sell": Decimal(1) if trade["side"] == "SELL" else Decimal(0),
                    ":price": Decimal(str(trade["price"])),
                    ":ts": timestamp,
                },
            )

            # ── 3. Agregados por minuto ────────────────────────
            minute_window = get_minute_window(str(trade["exchange_ts"]))
            window_key = f"{trade['symbol']}#{minute_window}"

            table_add.update_item(
                Key={"symbol": window_key},
                UpdateExpression="""
                    SET trades_count    = if_not_exists(trades_count, :zero) + :inc,
                        qty_bought      = if_not_exists(qty_bought, :zero) + :qty_buy,
                        qty_sold        = if_not_exists(qty_sold, :zero) + :qty_sell,
                        value_usd       = if_not_exists(value_usd, :zero) + :val,
                        buy_count       = if_not_exists(buy_count, :zero) + :buy,
                        sell_count      = if_not_exists(sell_count, :zero) + :sell,
                        last_price      = :price,
                        window_minute   = :minute
                """,
                ExpressionAttributeValues={
                    ":inc": Decimal(1),
                    ":zero": Decimal(0),
                    ":qty_buy": qty if trade["side"] == "BUY" else Decimal(0),
                    ":qty_sell": qty if trade["side"] == "SELL" else Decimal(0),
                    ":val": Decimal(str(trade["trade_value_usd"])),
                    ":buy": Decimal(1) if trade["side"] == "BUY" else Decimal(0),
                    ":sell": Decimal(1) if trade["side"] == "SELL" else Decimal(0),
                    ":price": Decimal(str(trade["price"])),
                    ":minute": minute_window,
                },
            )

            processed += 1
            print(f"✓ Trade procesado: {trade['symbol']}")

        except KeyError as e:
            # Error de datos malformados
            failed += 1
            print(f"[WARN] Trade malformado (falta campo {str(e)})")
            try:
                send_to_error_queue(trade, f"Campo faltante: {str(e)}")
            except:
                pass
            continue

        except Exception as e:
            # Error crítico (conexión, permiso, etc) → Deja que falle la Lambda
            print(f"[CRITICAL] Error crítico: {str(e)}")
            raise  # ← Esto hace que el batch vaya al SQS

    return {
        "status": "ok",
        "processed": processed,
        "failed": failed,
        "total": len(event["Records"])
    }