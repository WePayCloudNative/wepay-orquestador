#!/usr/bin/env bash
# ============================================================
# Crea las 6 colas de WePay, cada una en su nodo del clúster.
# Se ejecuta DESPUÉS de levantar los 2 Rabbit y ANTES de los MS.
# Es idempotente: si la cola ya existe con los mismos argumentos, no cambia nada.
#
# Uso:
#   RABBIT_USER=wepay RABBIT_PASS=xxx ./rabbitmq/crear-colas.sh
# Variables opcionales:
#   RABBIT_API  panel de cualquier nodo   (default http://localhost:15672)
#   NODE1       nodo de email y sms       (default rabbit@rabbitmq)
#   NODE2       nodo de facturación       (default rabbit@rabbitmq2)
# ============================================================
set -euo pipefail

: "${RABBIT_USER:?Falta RABBIT_USER}"
: "${RABBIT_PASS:?Falta RABBIT_PASS}"
API="${RABBIT_API:-http://localhost:15672}/api"
NODE1="${NODE1:-rabbit@rabbitmq}"
NODE2="${NODE2:-rabbit@rabbitmq2}"
DLX="ex.pedidos.dlx"

# crear_cola <nombre> <nodo> <argumentos JSON>
crear_cola() {
  echo "Creando $1 en $2"
  curl -sS -f -u "${RABBIT_USER}:${RABBIT_PASS}" -X PUT \
       -H "content-type: application/json" \
       -d "{\"durable\":true,\"node\":\"$2\",\"arguments\":$3}" \
       "${API}/queues/%2F/$1" -o /dev/null
}

# ---- Nodo 1: notificaciones al cliente ----
crear_cola q.cmd.email     "$NODE1" "{\"x-dead-letter-exchange\":\"$DLX\",\"x-dead-letter-routing-key\":\"q.cmd.email.dlq\"}"
crear_cola q.cmd.email.dlq "$NODE1" "{}"
crear_cola q.cmd.sms       "$NODE1" "{\"x-dead-letter-exchange\":\"$DLX\",\"x-dead-letter-routing-key\":\"q.cmd.sms.dlq\",\"x-message-ttl\":60000}"
crear_cola q.cmd.sms.dlq   "$NODE1" "{}"

# ---- Nodo 2: facturación ----
crear_cola q.cmd.facturacion     "$NODE2" "{\"x-dead-letter-exchange\":\"$DLX\",\"x-dead-letter-routing-key\":\"q.cmd.facturacion.dlq\",\"x-max-length\":100,\"x-overflow\":\"reject-publish-dlx\"}"
crear_cola q.cmd.facturacion.dlq "$NODE2" "{}"

echo
echo "Listo. Colas y su nodo:"
curl -sS -u "${RABBIT_USER}:${RABBIT_PASS}" "${API}/queues/%2F?columns=name,node" \
  | grep -o '"name":"[^"]*","node":"[^"]*"\|"node":"[^"]*","name":"[^"]*"' || true