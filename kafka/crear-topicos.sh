#!/usr/bin/env bash
# ============================================================
# Crea (o actualiza) los tópicos de WePay con su configuración por flujo.
# Ejecutar con el clúster Kafka levantado y ANTES de los microservicios.
# Es idempotente: si el tópico existe, solo vuelve a aplicar su configuración.
#
# Tópico                       Part. Rép.  Retención  Por qué
# orders.events                  3    3    7 días     eventos de negocio; auditoría y reportes los
#                                                     guardan en Oracle, Kafka solo los transporta
# audit.timeline                 3    3    30 días    traza de lo auditado; se conserva más para revisiones
# orders.events.DLT              1    3    30 días    fallos de reportes: tiempo para investigar y reprocesar
# orders.events.auditoria.DLT    1    3    30 días    fallos de auditoría: ídem
#
# Todos: cleanup.policy=delete (se borra lo vencido; no hay claves que compactar)
#        min.insync.replicas=2 (un mensaje se confirma cuando está en 2 de 3 brokers)
# ============================================================
set -euo pipefail

KAFKA="${KAFKA_CONTAINER:-kafka}"
BOOTSTRAP="${BOOTSTRAP:-kafka:29092}"

DIA=86400000   # 1 día en milisegundos

# nombre:particiones:retención_ms
TOPICOS=(
  "orders.events:3:$((7 * DIA))"
  "audit.timeline:3:$((30 * DIA))"
  "orders.events.DLT:1:$((30 * DIA))"
  "orders.events.auditoria.DLT:1:$((30 * DIA))"
)

for t in "${TOPICOS[@]}"; do
  IFS=: read -r nombre particiones retencion <<< "$t"
  config="cleanup.policy=delete,retention.ms=${retencion},min.insync.replicas=2"

  docker exec "$KAFKA" kafka-topics --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists --topic "$nombre" \
    --partitions "$particiones" --replication-factor 3

  # Si ya existía, igual se deja con la configuración de esta tabla
  docker exec "$KAFKA" kafka-configs --bootstrap-server "$BOOTSTRAP" \
    --alter --entity-type topics --entity-name "$nombre" --add-config "$config" >/dev/null
  echo "OK  $nombre  ($particiones particiones, retención $((retencion / DIA)) días)"
done
