"""
Producer: Coinbase WebSocket → Kinesis
Trades en tiempo real, con throttle para controlar el caudal.
"""

import json
import time
import boto3
import websocket  # pip install websocket-client

# ── Configuración ──────────────────────────────────────────────
STREAM_NAME = "broker-PC4"
REGION = "us-east-1"

SYMBOLS = ["BTC-USD", "ETH-USD", "SOL-USD"]

COINBASE_WS_URL = "wss://ws-feed.exchange.coinbase.com"

# Intervalo mínimo entre envíos (segundos)
THROTTLE_SECONDS = 5

# ── Cliente Kinesis ────────────────────────────────────────────
kinesis = boto3.client("kinesis", region_name=REGION)

# ── Control de throttle ───────────────────────────────────────
last_sent = 0


def transform_trade(data: dict) -> dict:
    """
    Campos de Coinbase (type=match / last_match):
        product_id  = par (BTC-USD)
        price       = precio
        size        = cantidad
        side        = buy / sell
        trade_id    = id del trade
        time        = timestamp ISO 8601
    """
    price = float(data["price"])
    size = float(data["size"])
    return {
        "trade_id": data["trade_id"],
        "symbol": data["product_id"],
        "price": price,
        "quantity": size,
        "trade_value_usd": round(price * size, 2),
        "side": data["side"].upper(),
        "exchange_ts": data["time"],
        "ingestion_ts": int(time.time() * 1000),
    }


def on_message(ws, message):
    global last_sent
    now = time.time()

    # Descarta trades dentro de la ventana de throttle
    if now - last_sent < THROTTLE_SECONDS:
        return

    data = json.loads(message)

    # Solo procesamos trades reales
    if data.get("type") not in ("match", "last_match"):
        return

    trade = transform_trade(data)

    kinesis.put_record(
        StreamName=STREAM_NAME,
        Data=json.dumps(trade),
        PartitionKey=trade["symbol"],
    )

    print(f"[{trade['symbol']}] {trade['side']:>4}  "
          f"price={trade['price']:<12}  qty={trade['quantity']:<14}  "
          f"value=${trade['trade_value_usd']:,.2f}")

    last_sent = now


def on_error(ws, error):
    print(f"[ERROR] {error}")


def on_close(ws, close_status, close_msg):
    print(f"[CLOSED] status={close_status}  msg={close_msg}")
    print("Reconectando en 5s...")
    time.sleep(5)
    start()


def on_open(ws):
    subscribe_msg = {
        "type": "subscribe",
        "channels": [
            {
                "name": "matches",
                "product_ids": SYMBOLS,
            }
        ],
    }
    ws.send(json.dumps(subscribe_msg))
    print(f"Conectado a Coinbase WS — siguiendo: {', '.join(SYMBOLS)}")
    print(f"Enviando a Kinesis stream: {STREAM_NAME} ({REGION})")
    print(f"Throttle: 1 trade cada {THROTTLE_SECONDS}s")
    print("-" * 70)


def start():
    ws = websocket.WebSocketApp(
        COINBASE_WS_URL,
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
    )
    ws.run_forever(ping_interval=30, ping_timeout=10)


if __name__ == "__main__":
    start()