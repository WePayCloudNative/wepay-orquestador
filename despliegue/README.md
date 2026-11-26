# Despliegue de WePay (AWS)

Esta carpeta tiene la configuración **que corre en AWS**. Cada requisito de infraestructura
tiene su propio archivo `docker-compose`, y todos comparten la red Docker `wepay-net`.

| Archivo | Qué levanta | Requisito |
|---|---|---|
| `docker-compose.rabbitmq-cluster.yml` | 2 nodos RabbitMQ en clúster | Clúster de RabbitMQ |
| `docker-compose.kafka-cluster.yml` | 1 Zookeeper + 3 brokers Kafka (replicación 3) | Kafka con Zookeeper y brokers |
| `docker-compose.kafka-ui.yml` | Kafka UI con inicio de sesión | Administrar brokers y tópicos |
| `docker-compose.yml` | Microservicios (BFF, clientes, catálogo, pedidos, notificaciones, auditoría, reportes) | Productores y consumidores Kafka |

## Arquitectura en AWS

```
                    API Gateway (JWT Entra ID)
                             │
 ec2-microservicios ─────────┼──────────────────────────────────────────┐
 │  api-bff ─► ms-clientes, ms-catalogo, ms-pedidos, ms-auditoria, ms-reportes
 │  ms-pedidos ──► Kafka: orders.events ──► ms-auditoria ──► audit.timeline
 │                                      └─► ms-reportes
 │  Kafka: zookeeper + kafka, kafka2, kafka3   │  Kafka UI (solo para la demo)
 └──────────────────────────────────────────────────────────────────────┘
 ec2-rabbitmq:  rabbitmq + rabbitmq2  ◄── ms-pedidos (publica) / ms-notificaciones (consume)
 Amazon RDS Oracle: un esquema por microservicio (clientes, pedidos, auditoria, reportes)
```

## Cómo levantarlo

1. Copia `.env.example` como `.env` y completa los valores (el `.env` no se sube a git).
2. **RabbitMQ** (en `ec2-rabbitmq`):
   ```bash
   docker compose -f docker-compose.rabbitmq-cluster.yml up -d
   RABBIT_USER=... RABBIT_PASS=... ../rabbitmq/crear-colas.sh
   ```
3. **Kafka** (en `ec2-microservicios`):
   ```bash
   docker compose -f docker-compose.kafka-cluster.yml up -d
   ./kafka/crear-topicos.sh
   ```
4. **Microservicios**:
   ```bash
   docker compose up -d
   ```
5. **Kafka UI** (solo cuando se necesita):
   ```bash
   docker compose -f docker-compose.kafka-ui.yml up -d     # levantar
   docker compose -f docker-compose.kafka-ui.yml stop      # apagar
   ```

> Para probar todo en un solo PC: usar `RABBIT_ADDRESSES=rabbitmq:5672,rabbitmq2:5672` y
> levantar los cuatro archivos en la misma máquina. Oracle sigue siendo el de RDS.

## Comprobaciones útiles

```bash
# Brokers registrados (esperado: [1, 2, 3])
docker exec kafka zookeeper-shell zookeeper:2181 ls /brokers/ids

# Réplicas y líder de cada partición
docker exec kafka kafka-topics --bootstrap-server kafka:29092 --describe --topic orders.events

# Lag de los consumidores (0 = al día)
docker exec kafka kafka-consumer-groups --bootstrap-server kafka:29092 --describe --group wepay-reportes-group

# Nodos del clúster RabbitMQ
docker exec rabbitmq rabbitmqctl cluster_status
```

## Decisiones

- **Replicación 3 y `min.insync.replicas=2`:** cada mensaje queda en los 3 brokers y se confirma
  con al menos 2. Si cae un broker la tienda sigue funcionando; con 2 caídos Kafka rechaza
  escrituras para no arriesgar perder datos.
- **Sin puertos de Kafka publicados:** solo los microservicios (en la red Docker) lo alcanzan.
- **Puertos de auditoría, reportes y pedidos en `127.0.0.1`:** no son accesibles desde internet,
  solo a través del BFF.
- **Kafka UI con inicio de sesión** y levantada solo para la demo.
- **Contraseñas solo en `.env`**, nunca en los archivos del repo.
