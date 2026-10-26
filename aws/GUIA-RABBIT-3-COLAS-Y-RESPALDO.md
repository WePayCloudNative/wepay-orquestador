# RabbitMQ: 3 colas + 3 DLQ y broker de respaldo (Experiencia 2)

## Diseño

**Rabbit 1 (`ec2-rabbitmq`): broker principal.** `ms-pedidos` publica en el exchange `ex.pedidos` (topic) con la routing key `pedido.estado.<estado>`.

| Cola | Binding | Configuración | DLQ |
|---|---|---|---|
| `q.cmd.email` | `pedido.estado.*` (todos los cambios) | Reintentos | `q.cmd.email.dlq` |
| `q.cmd.sms` | `pedido.estado.despachado`, `pedido.estado.cancelado` | TTL 60 s | `q.cmd.sms.dlq` |
| `q.cmd.facturacion` | `pedido.estado.entregado` | Máx. 100, `reject-publish-dlx` | `q.cmd.facturacion.dlq` |

- Las DLQ cuelgan de `ex.pedidos.dlx` (topic).
- La topología se declara igual en `ms-pedidos` y `ms-notificaciones` (`config/RabbitMQConfig.java`).
- `ms-notificaciones` consume las 3 colas así:
  - Entre 2 y 5 consumidores por cola, con prefetch 10.
  - 1 intento y 3 reintentos (a 1 s, 2 s y 4 s). Si todos fallan, el mensaje va a la DLQ.

**Rabbit 2 (`ec2-rabbitmq-2`): broker de respaldo y auditoría.** Dos shovels leen desde el Rabbit 1 y guardan copias en dos colas:

- `q.respaldo.pedidos`: copia de todos los eventos de `ex.pedidos`.
- `q.respaldo.fallidos`: copia de todo lo que pasa por `ex.pedidos.dlx`.

La policy `retencion-respaldo` conserva los mensajes 7 días, con un máximo de 50.000 por cola. Este broker se administra por policy, no por código.

> En el Rabbit 1 aparecen 2 colas `amq.gen-...`: son las colas temporales de los shovels. No les quitan mensajes a las 6 colas.

---

## Despliegue en AWS

### 1. Imágenes (desde tu PC)
```bash
cd wepay-ms-pedidos && docker build -t joseave/wepay-ms-pedidos:latest . && docker push joseave/wepay-ms-pedidos:latest
cd ../wepay-ms-notificaciones && docker build -t joseave/wepay-ms-notificaciones:latest . && docker push joseave/wepay-ms-notificaciones:latest
```

### 2. Borrar la cola antigua (panel del Rabbit 1)
Queues → `q.cmd.email` → **Delete**. La cola vieja no tiene argumentos de DLX. Si no la borras, Spring falla con `PRECONDITION_FAILED - inequivalent arg 'x-dead-letter-exchange'`.

### 3. ec2-microservicios (`~/wepay/docker-compose.yml`)
En el servicio de notificaciones, agrega esta línea en `environment:`:
```yaml
      APP_FALLA_FACTURACION: ${APP_FALLA_FACTURACION:-false}
```
Después actualiza los contenedores:
```bash
cd ~/wepay && docker compose pull && docker compose up -d
```

### 4. Plugin shovel en el Rabbit 1 (para "Move messages" desde la DLQ)
Copia `rabbitmq/enabled_plugins` a `~/rabbitmq/` en `ec2-rabbitmq`. Luego agrega esta línea en `volumes:` de su `docker-compose.yml`:
```yaml
      - ./enabled_plugins:/etc/rabbitmq/enabled_plugins:ro
```
Aplica el cambio con `docker compose up -d`.

### 5. Crear ec2-rabbitmq-2
1. **Security group `sg-rabbitmq2`:**
   - 22 desde Mi IP
   - 15672 desde Mi IP

   No necesita el 5672 abierto.
2. **En `sg-rabbitmq`:** agrega una regla de entrada **5672 desde `sg-rabbitmq2`**.
3. **EC2:**
   - Nombre `ec2-rabbitmq-2`, t3.small, 10 GB, Ubuntu 24.04
   - `vockey`, `LabInstanceProfile`, `sg-rabbitmq2`
   - Si puedes, en otra AZ distinta a la del Rabbit 1
4. Instala Docker y el swap igual que en `ec2-rabbitmq`.
5. Copia los 3 archivos a la instancia (desde `wepay-orquestador`):
   ```bash
   scp -i labsuser.pem aws/ec2-rabbitmq-2/docker-compose.yml rabbitmq/enabled_plugins rabbitmq/setup-rabbit2.sh ubuntu@<IP_PUBLICA_RABBIT2>:~/rabbitmq2/
   ```
   Antes crea la carpeta en la instancia con `mkdir ~/rabbitmq2`.
6. En la instancia, crea el `.env`, levanta el broker y ejecuta el script:
   ```bash
   cd ~/rabbitmq2
   printf 'RABBIT_USER=wepay\nRABBIT_PASS=LA_MISMA_CLAVE_DEL_RABBIT_1\n' > .env
   docker compose up -d
   nc -zv 172.31.22.184 5672
   chmod +x setup-rabbit2.sh
   set -a; . ./.env; set +a; RABBIT1_HOST=172.31.22.184 ./setup-rabbit2.sh
   ```
   El script debe terminar con los 2 shovels en `running`.

---

## Pruebas y evidencias

Ya se probaron en local con este mismo código.

Puedes ejecutarlas de dos formas:
- **Por API Gateway**, con `$token`.
- **Por el BFF**, con `PUT /api/pedidos/{id}/status` y el body `{"status":"..."}`.

| # | Prueba | Pasos | Resultado esperado | IL |
|---|---|---|---|---|
| 1 | Ruteo | PUT con `ACEPTADO`, `EN_PREPARACION`, `DESPACHADO` y `ENTREGADO` | 4 `[EMAIL]`, 1 `[SMS]` (despachado) y 1 `[FACTURACION]` (entregado) | 2.2 |
| 2 | Reintentos y DLQ | `APP_FALLA_FACTURACION=true docker compose up -d <servicio-notificaciones>`, luego PUT con `ENTREGADO` | 4 líneas "Procesando pedido" (1 s, 2 s, 4 s), luego `Retries exhausted` y `q.cmd.facturacion.dlq` = 1 | 2.3 |
| 3 | TTL | Detén notificaciones, PUT con `CANCELADO` y espera 60 s | `q.cmd.sms` pasa de 1 a 0 y `q.cmd.sms.dlq` = 1 | 2.3 |
| 4 | Mensaje venenoso | Panel → Exchanges → `ex.pedidos` → Publish message, con routing key `pedido.estado.x` y payload `hola` | `q.cmd.email.dlq` = 1 (MessageConversionException, sin reintento) | 2.3 |
| 5 | Carga | Con notificaciones detenido, envía 200 PUT y luego vuelve a levantarlo | Email llega a 202 en Ready y se vacía en unos 30 s. Los consumidores suben solos de 2 a 4 (captura la pestaña Consumers y el gráfico) | RA2 |
| 6 | Respaldo | Panel del Rabbit 2 | `q.respaldo.pedidos` y `q.respaldo.fallidos` con mensajes y policy `retencion-respaldo`. Admin → Shovel Status muestra 2 en running | 2.1 / 2.3 |
| 7 | Reprocesar | `APP_FALLA_FACTURACION=false`. Luego, en el panel, `q.cmd.facturacion.dlq` → Move messages → `q.cmd.facturacion` | Se genera la boleta | 2.3 |

Bucle de carga en PowerShell, usando el mismo `$token`:
```powershell
$api = "https://afufg51ouh.execute-api.us-east-1.amazonaws.com"
$h = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
1..200 | % { Invoke-RestMethod -Method Put -Uri "$api/api/pedidos/1/status" -Headers $h -Body '{"status":"EN_PREPARACION"}' | Out-Null }
```

**Capturas mínimas:**
- Queues del Rabbit 1, con las 6 colas y las etiquetas DLX, TTL y Lim.
- Bindings de `ex.pedidos` y de `ex.pedidos.dlx`.
- Logs de cada prueba.
- Gráfico de la prueba de carga.
- Queues y Shovel Status del Rabbit 2.

## Seguridad y costos
- Restringe el 15672 de los dos Rabbit a Mi IP.
- El Rabbit 2 cuesta unos US$0,02 por hora encendido. Con End Lab se detiene. Su IP privada y la del Rabbit 1 no cambian, así que los shovels se reconectan solos al iniciar el lab.
