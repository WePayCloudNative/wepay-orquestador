#!/usr/bin/env bash
# ============================================================
# Administración del clúster Kafka de WePay desde la terminal.
# Usa las herramientas oficiales de Kafka dentro del contenedor del broker.
#
#   ./kafka/admin.sh brokers                          brokers del clúster
#   ./kafka/admin.sh topicos                          lista de tópicos
#   ./kafka/admin.sh describir <tópico>               particiones, líderes, réplicas y config
#   ./kafka/admin.sh crear <tópico> [part] [rép]      crea un tópico (por defecto 3 y 3)
#   ./kafka/admin.sh config <tópico> <clave=valor,…>  cambia su configuración
#   ./kafka/admin.sh particiones <tópico> <n>         aumenta particiones (nunca se reducen)
#   ./kafka/admin.sh borrar <tópico>                  elimina un tópico (pide confirmación)
#   ./kafka/admin.sh grupos                           lista los consumer groups
#   ./kafka/admin.sh grupo <grupo>                    miembros, offsets y lag por partición
#   ./kafka/admin.sh reset <grupo> <tópico> <earliest|latest> [--ejecutar]
#                                                     mueve los offsets de un grupo (con el
#                                                     consumidor detenido); sin --ejecutar
#                                                     solo muestra qué haría
#
# Variables opcionales: KAFKA_CONTAINER (kafka), BOOTSTRAP (kafka:29092)
# ============================================================
set -euo pipefail

KAFKA="${KAFKA_CONTAINER:-kafka}"
BOOTSTRAP="${BOOTSTRAP:-kafka:29092}"
PROTEGIDOS="orders.events audit.timeline orders.events.DLT orders.events.auditoria.DLT"

k() { docker exec -i "$KAFKA" "$@" --bootstrap-server "$BOOTSTRAP"; }

uso() { sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

falta() { [ -n "${1:-}" ] || { echo "Falta: $2"; echo; uso; }; }

case "${1:-}" in
  brokers)
    docker exec "$KAFKA" zookeeper-shell zookeeper:2181 ls /brokers/ids 2>/dev/null | tail -1 | sed 's/^/IDs: /'
    k kafka-broker-api-versions | grep -o '^[^ ]* (id: [0-9]*' | sed 's/ (id: / → broker /'
    ;;
  topicos)
    k kafka-topics --list
    ;;
  describir)
    falta "${2:-}" "tópico"
    k kafka-topics --describe --topic "$2"
    echo; echo "Configuración propia del tópico:"
    k kafka-configs --describe --entity-type topics --entity-name "$2" | sed -n '2,$p'
    ;;
  crear)
    falta "${2:-}" "tópico"
    k kafka-topics --create --topic "$2" --partitions "${3:-3}" --replication-factor "${4:-3}"
    ;;
  config)
    falta "${2:-}" "tópico"; falta "${3:-}" "clave=valor (ej: retention.ms=3600000)"
    k kafka-configs --alter --entity-type topics --entity-name "$2" --add-config "$3"
    k kafka-configs --describe --entity-type topics --entity-name "$2"
    ;;
  particiones)
    falta "${2:-}" "tópico"; falta "${3:-}" "número de particiones"
    k kafka-topics --alter --topic "$2" --partitions "$3"
    k kafka-topics --describe --topic "$2" | head -1
    ;;
  borrar)
    falta "${2:-}" "tópico"
    if [[ " $PROTEGIDOS " == *" $2 "* ]]; then
      echo "⚠ $2 es un tópico del sistema: borrarlo deja a los microservicios sin sus eventos."
    fi
    read -r -p "Escribe el nombre del tópico para confirmar: " confirma
    [ "$confirma" = "$2" ] || { echo "Cancelado."; exit 1; }
    k kafka-topics --delete --topic "$2"
    echo "Eliminado: $2"
    ;;
  grupos)
    k kafka-consumer-groups --list
    ;;
  grupo)
    falta "${2:-}" "grupo"
    k kafka-consumer-groups --describe --group "$2"
    echo; k kafka-consumer-groups --describe --group "$2" --members
    ;;
  reset)
    falta "${2:-}" "grupo"; falta "${3:-}" "tópico"; falta "${4:-}" "earliest o latest"
    modo="--dry-run"; [ "${5:-}" = "--ejecutar" ] && modo="--execute"
    k kafka-consumer-groups --reset-offsets --group "$2" --topic "$3" --to-"$4" "$modo"
    [ "$modo" = "--dry-run" ] && echo "(simulación: agrega --ejecutar para aplicarlo, con el consumidor detenido)"
    ;;
  *)
    uso
    ;;
esac
