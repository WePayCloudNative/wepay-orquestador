#!/usr/bin/env bash
# ============================================================
# Configura el RabbitMQ 2 ("broker de respaldo y auditoría").
#
# Crea en el Rabbit 2:
#   - q.respaldo.pedidos   copia de todos los eventos de ex.pedidos (Rabbit 1)
#   - q.respaldo.fallidos  copia de todo lo que cae a las DLQ (ex.pedidos.dlx)
#   - policy "retencion-respaldo": 7 días y máx. 50.000 mensajes por cola
#   - 2 shovels que corren DENTRO del Rabbit 2 y leen desde el Rabbit 1
#
# Usa la API HTTP del panel (puerto 15672), así que solo necesita curl.
# Es idempotente: se puede ejecutar varias veces.
#
# Variables:
#   RABBIT2_API   URL del panel del Rabbit 2       (default http://localhost:15672)
#   RABBIT_USER   usuario (el mismo en ambos Rabbit)
#   RABBIT_PASS   clave   (si tiene @ : / # ? escríbela URL-encoded)
#   RABBIT1_HOST  host del Rabbit 1 VISTO DESDE el Rabbit 2
#                 local: rabbitmq      AWS: 172.31.22.184 (IP privada)
#
# Ejemplo AWS (en ec2-rabbitmq-2):
#   RABBIT_USER=wepay RABBIT_PASS=xxx RABBIT1_HOST=172.31.22.184 ./setup-rabbit2.sh
# Ejemplo local (desde wepay-orquestador, con Git Bash):
#   RABBIT2_API=http://localhost:15673 RABBIT_USER=wepay RABBIT_PASS=xxx RABBIT1_HOST=rabbitmq ./rabbitmq/setup-rabbit2.sh
# ============================================================
set -euo pipefail

: "${RABBIT_USER:?Falta RABBIT_USER}"
: "${RABBIT_PASS:?Falta RABBIT_PASS}"
: "${RABBIT1_HOST:?Falta RABBIT1_HOST}"
API="${RABBIT2_API:-http://localhost:15672}/api"
SRC_URI="amqp://${RABBIT_USER}:${RABBIT_PASS}@${RABBIT1_HOST}:5672"

put() {
  echo "PUT $1"
  curl -sS -f -u "${RABBIT_USER}:${RABBIT_PASS}" -X PUT \
       -H "content-type: application/json" -d "$2" "${API}$1" -o /dev/null
}

# 1) Colas de respaldo (durables)
put "/queues/%2F/q.respaldo.pedidos"  '{"durable":true}'
put "/queues/%2F/q.respaldo.fallidos" '{"durable":true}'

# 2) Policy de retención: administración por policy (en el Rabbit 1 se usan argumentos en código)
put "/policies/%2F/retencion-respaldo" \
  '{"pattern":"^q\\.respaldo\\.","apply-to":"queues","definition":{"message-ttl":604800000,"max-length":50000}}'

# 3) Shovel de eventos: copia todo lo publicado en ex.pedidos
put "/parameters/shovel/%2F/respaldo-pedidos" "{\"value\":{
  \"src-protocol\":\"amqp091\",\"src-uri\":\"${SRC_URI}\",
  \"src-exchange\":\"ex.pedidos\",\"src-exchange-key\":\"pedido.#\",
  \"dest-protocol\":\"amqp091\",\"dest-uri\":\"amqp://\",
  \"dest-queue\":\"q.respaldo.pedidos\",\"ack-mode\":\"on-confirm\"}}"

# 4) Shovel de fallidos: copia todo lo que pasa por ex.pedidos.dlx
put "/parameters/shovel/%2F/respaldo-fallidos" "{\"value\":{
  \"src-protocol\":\"amqp091\",\"src-uri\":\"${SRC_URI}\",
  \"src-exchange\":\"ex.pedidos.dlx\",\"src-exchange-key\":\"#\",
  \"dest-protocol\":\"amqp091\",\"dest-uri\":\"amqp://\",
  \"dest-queue\":\"q.respaldo.fallidos\",\"ack-mode\":\"on-confirm\"}}"

echo
echo "Listo. Estado de los shovels (debe decir running):"
sleep 3
curl -sS -u "${RABBIT_USER}:${RABBIT_PASS}" "${API}/shovels" \
  | grep -o '"name":"[^"]*"\|"state":"[^"]*"' | paste - - || true
