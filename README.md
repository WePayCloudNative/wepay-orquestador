# WePay - Orquestador

Configuración de infraestructura de WePay: **la misma que corre en AWS**. Cada requisito de infraestructura
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

## Contenido del repositorio

```
docker-compose.rabbitmq-cluster.yml   clúster RabbitMQ (2 nodos)
docker-compose.kafka-cluster.yml      Zookeeper + 3 brokers Kafka
docker-compose.kafka-ui.yml           Kafka UI
docker-compose.yml                    microservicios
rabbitmq/                             configuración del clúster y script de colas
kafka/crear-topicos.sh                tópicos con 3 réplicas, retención y cleanup por flujo
kafka/admin.sh                        administración: tópicos, configuración y consumer groups
.env.example                          variables necesarias (sin valores reales)
```

El código de cada microservicio está en su propio repositorio de la organización
[WePayCloudNative](https://github.com/WePayCloudNative); aquí se usan sus imágenes de Docker Hub (`joseave/*`).

## Cómo levantarlo

1. Copia `.env.example` como `.env` y completa los valores (el `.env` no se sube a git).
2. **RabbitMQ** (en `ec2-rabbitmq`):
   ```bash
   docker compose -f docker-compose.rabbitmq-cluster.yml up -d
   RABBIT_USER=... RABBIT_PASS=... ./rabbitmq/crear-colas.sh
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

## Tópicos y su configuración

| Tópico | Particiones | Réplicas | Retención | Cleanup | Flujo |
|---|---|---|---|---|---|
| `orders.events` | 3 | 3 | 7 días | delete | ms-pedidos → ms-auditoria y ms-reportes |
| `audit.timeline` | 3 | 3 | 30 días | delete | ms-auditoria publica cada evento registrado |
| `orders.events.DLT` | 1 | 3 | 30 días | delete | eventos que ms-reportes no pudo procesar |
| `orders.events.auditoria.DLT` | 1 | 3 | 30 días | delete | eventos que ms-auditoria no pudo procesar |

Todos con `min.insync.replicas=2`. Los eventos duran 7 días porque auditoría y reportes ya los guardan
en Oracle; las DLT y la traza de auditoría duran 30 para dar tiempo a investigar.

## Administrar Kafka

```bash
./kafka/admin.sh brokers                                   # brokers del clúster
./kafka/admin.sh topicos                                   # tópicos
./kafka/admin.sh describir orders.events                   # particiones, líderes, réplicas y config
./kafka/admin.sh crear prueba 3 3                          # crear
./kafka/admin.sh config prueba retention.ms=3600000        # cambiar configuración
./kafka/admin.sh particiones prueba 6                      # aumentar particiones
./kafka/admin.sh borrar prueba                             # eliminar (pide confirmación)
./kafka/admin.sh grupos                                    # consumer groups
./kafka/admin.sh grupo wepay-reportes-group                # offsets, lag y miembros
./kafka/admin.sh reset wepay-reportes-group orders.events earliest   # reprocesar (simulación)
```

Lo mismo se puede hacer desde la Kafka UI.

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
