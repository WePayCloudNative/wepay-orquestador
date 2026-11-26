#!/usr/bin/env bash
# ============================================================
# Crea los tópicos de WePay con 3 réplicas (uno por broker).
# Ejecutar con el clúster Kafka levantado y ANTES de los microservicios.
# Es idempotente: si el tópico ya existe, no lo toca.
#
#   orders.events                 3 particiones  (ms-pedidos -> auditoría y reportes)
#   audit.timeline                3 particiones  (ms-auditoria publica lo que registró)
#   orders.events.DLT             1 partición    (fallos de ms-reportes)
#   orders.events.auditoria.DLT   1 partición    (fallos de ms-auditoria)
# ============================================================
set -euo pipefail

for t in orders.events:3 audit.timeline:3 orders.events.DLT:1 orders.events.auditoria.DLT:1; do
  docker exec kafka kafka-topics --bootstrap-server kafka:29092 \
    --create --if-not-exists --topic "${t%%:*}" --partitions "${t##*:}" --replication-factor 3
done

docker exec kafka kafka-topics --bootstrap-server kafka:29092 --describe --topic orders.events
