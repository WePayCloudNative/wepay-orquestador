

# WePay - Orquestador de Microservicios 🚀

Este repositorio central funciona como el **orquestador de infraestructura** para el sistema WePay. Contiene la configuración de despliegue mediante Docker Compose para levantar todos los microservicios backend de forma simultánea e interconectada en un entorno de desarrollo local.

> **Despliegue en AWS:** la configuración que corre en producción (clúster RabbitMQ de 2 nodos,
> clúster Kafka de 3 brokers, Kafka UI, Oracle en RDS) está en [`despliegue/`](despliegue/README.md).
> Los archivos de esta raíz son para desarrollo local.

## 🏗️ Arquitectura del Sistema

El ecosistema está compuesto por los siguientes servicios, gestionados mediante Submódulos de Git:

- **BFF (Backend for Frontend):** Puerta de entrada principal. Orquesta llamadas, valida tokens de Entra ID y evalúa roles (Puerto 8081).
- **MS Usuarios:** Gestiona la información de perfil y asignación de roles (Puerto 8083).
- **MS Catálogo:** Gestiona la lista de productos disponibles para compra (Puerto 8084).
- **MS Pedidos:** Gestiona el cálculo, creación y lectura del historial de compras (Puerto 8085).

*Nota: La arquitectura está diseñada sin dependencias de localhost directo entre servicios. Los servicios se comunican a través de la red interna de Docker usando los nombres de los contenedores.*

---

## ⚙️ Requisitos Previos

Para ejecutar este proyecto en tu máquina local, necesitas tener instalado:
1. [Git](https://git-scm.com/)
2. [Docker Desktop](https://www.docker.com/products/docker-desktop/) (o Docker Engine + Docker Compose)
3. Credenciales válidas de Microsoft Entra ID (Tenant ID y Client ID).

---

## 🚀 Guía de Instalación y Ejecución

Sigue estos pasos exactos para descargar el código fuente y levantar la arquitectura completa.

### 1. Clonar el repositorio
Dado que este proyecto utiliza submódulos de Git, debes clonarlo de forma recursiva para descargar también el código de las carpetas internas de cada microservicio:

```bash
git clone --recurse-submodules https://github.com/racoonius-programmer/wepay-orquestador.git
cd wepay-orquestador

```

*(Si ya clonaste el proyecto sin el flag recursivo, puedes descargar el contenido de los submódulos ejecutando `git submodule update --init --recursive`)*.

### 2. Configurar Variables de Entorno (.env)

El BFF requiere variables de configuración para validar la autenticación. En la **raíz del proyecto** (donde se encuentra el `docker-compose.yml`), crea un archivo llamado `.env` e ingresa los valores correspondientes al entorno de desarrollo:

```env
ENTRA_ISSUER_URI=[https://login.microsoftonline.com/](https://login.microsoftonline.com/)<TU_TENANT_ID_AQUI>/v2.0
ENTRA_API_CLIENT_ID=<TU_CLIENT_ID_AQUI>

VITE_ENTRA_TENANT_ID=...
VITE_SPA_CLIENT_ID=...
VITE_API_CLIENT_ID=...
VITE_BFF_BASE_URL=http://localhost:8081 (puerto por defecto)

```

### 3. Levantar los Contenedores

Abre tu terminal en la raíz del proyecto y ejecuta el siguiente comando. Docker se encargará de descargar la imagen desde Docker Hub, descargar los archivos y ejecutarlos en los puertos establecidos.
- Front: Puerto 5173
- BFF: 8081
- MS-Clientes: 8083
- MS-Catalogo: 8084
- MS-Pedidos: 8085
(Mismos puertos se usan en Docker)

```bash
docker compose pull
docker compose up --d

```

**¡Listo!** El sistema estará operativo en unos segundos. Podrás ver los logs unificados de los 4 servicios en tu terminal.

---

## 🧪 Cómo Probar el Entorno

Entra al Front mediante localhost (5173 es el puerto por defecto)  
```bash
http://localhost:5173/
```
Todas las llamadas hacia el backend desde el cliente (Frontend/Postman/cURL) deben dirigirse exclusivamente al puerto del BFF (**8081**).

Asegúrate de generar un token JWT válido de usuario desde la plataforma de Microsoft Entra y utiliza ese token como `Bearer Auth`.

**Ejemplo de prueba de integridad (Obtener historial de pedidos):**
(Solo funciona si el Front corre en local)

```bash
curl -i http://localhost:8081/api/pedidos \
  -H "Authorization: Bearer <TU_TOKEN_JWT>"

```

---

## 🛠️ Notas de Desarrollo
* **Detener los servicios:** Para apagar el ecosistema de forma limpia y liberar los puertos, presiona `Ctrl + C` en la terminal donde se ejecutan los logs, o ejecuta `docker compose down` en una terminal paralela.
