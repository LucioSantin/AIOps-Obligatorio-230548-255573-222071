# Despliegue de PharmaGo en Kubernetes (Minikube)

Esta guía describe cómo desplegar la aplicación PharmaGo en un cluster de Kubernetes usando Minikube con 3 nodos.

## Arquitectura

Componentes:

- **Frontend**: pharmago-ui
- **Backend**: pharmago-api-gateway, pharmago-users-service, pharmago-pharmacy-service
- **Base de datos**: pharmago-db (SQL Server Express)
- **Telemetría y observabilidad**: otlp-collector, prometheus, grafana, elasticsearch, kibana, fluent-bit

Distribución en nodos (etiqueta `node-type`):

| Nodo | `node-type` | Qué corre |
|---|---|---|
| `minikube` | `all` | Frontend, base de datos, observabilidad y **un** microservicio de backend |
| `minikube-m02` | `backend` | Un microservicio de backend |
| `minikube-m03` | `backend` | Un microservicio de backend |

Los microservicios de backend tienen una regla de `podAntiAffinity` obligatoria: dos microservicios distintos nunca comparten nodo. Por eso hacen falta 3 nodos aptos para backend (uno por microservicio). Qué microservicio cae en cada nodo lo decide el scheduler. Las réplicas de un mismo microservicio comparten su nodo (`podAffinity` obligatoria hacia el propio servicio). `fluent-bit` y `node-exporter` son DaemonSets y corren en los 3 nodos.

**Requisito de memoria**: Cada nodo de Minikube recibe la memoria indicada en `--memory`. El nodo `minikube` necesita al menos 5-6GB de RAM para soportar Elasticsearch (1.5Gi), Kibana (2Gi), SQL Server Express (1.5Gi) y el resto de servicios.

## Prerrequisitos

1. **Minikube** instalado y configurado
2. **kubectl** instalado y configurado
3. **Docker** instalado (para construir las imágenes)

## Configuración Inicial

### 1. Crear cluster Minikube (3 nodos, 6GB RAM)

```bash
# Crear cluster de 3 nodos con suficiente memoria para telemetría (Elasticsearch, Kibana, etc.)
minikube start --nodes 3 --memory=6144 --cpus=4

# Verificar nodos (minikube, minikube-m02, minikube-m03)
kubectl get nodes
```

**Importante**: Usa al menos 6GB de RAM. Con menos, Elasticsearch y otros pods de observabilidad pueden fallar por OOM. Si el cluster ya existía con 1 nodo, hay que recrearlo (`minikube delete`) o agregar nodos con `minikube node add`.

### 2. Etiquetar nodos

Los scripts `apply-k8s.sh` / `apply-k8s.ps1` etiquetan los nodos automáticamente (el primero `node-type=all`, el resto `node-type=backend`). Si despliegas manualmente:
```bash
kubectl label nodes minikube node-type=all --overwrite
kubectl label nodes minikube-m02 node-type=backend --overwrite
kubectl label nodes minikube-m03 node-type=backend --overwrite

# Verificar
kubectl get nodes -L node-type
```

### 3. Construir y cargar imágenes Docker

**IMPORTANTE**: Usa `minikube image load` para cargar las imágenes en Minikube (no `minikube docker-env`).

#### Opción 1: Script automatizado (Recomendado)

```bash
cd k8s
chmod +x build-images.sh
./build-images.sh          # Windows: .\build-images.ps1
```

Cada imagen queda etiquetada con un tag versionado y con `:latest` (ver [Despliegues seguros](#despliegues-seguros-sin-downtime)).

#### Opción 2: Manual

Desde el directorio `Implementacion K8S/Codigo`:

```bash
# Construir imágenes de backend
cd Backend
docker build -f PharmaGo.UsersService/Dockerfile -t pharmago-users-service:latest .
minikube image load pharmago-users-service:latest

docker build -f PharmaGo.PharmacyService/Dockerfile -t pharmago-pharmacy-service:latest .
minikube image load pharmago-pharmacy-service:latest

docker build -f PharmaGo.ApiGateway/Dockerfile -t pharmago-api-gateway:latest .
minikube image load pharmago-api-gateway:latest

# Construir imagen de frontend
cd ../Frontend
docker build -f Dockerfile -t pharmago-ui:latest .
minikube image load pharmago-ui:latest
```

**Nota**: `minikube image load` carga las imágenes en todos los nodos de Minikube.

## Despliegue

**IMPORTANTE**: Asegúrate de haber construido y cargado las imágenes Docker primero (paso 3).

### Opción 1: Script automatizado (Recomendado)

```bash
cd k8s
chmod +x apply-k8s.sh
./apply-k8s.sh          # Windows: .\apply-k8s.ps1
```

### Opción 2: Despliegue manual

```bash
cd k8s

# 1. Namespace
kubectl apply -f namespace.yaml

# 2. Secrets
kubectl apply -f secrets/db-secret.yaml

# 3. ConfigMaps
kubectl apply -f configmaps/

# 4. PersistentVolumes
kubectl apply -f persistent-volumes/

# 5. Database
kubectl apply -f services/ops/db-service.yaml
kubectl apply -f deployments/ops/db-deployment.yaml
kubectl wait --for=condition=ready pod -l app=pharmago-db -n pharmago --timeout=300s

# 6. Ops services (Elasticsearch primero)
kubectl apply -f services/ops/elasticsearch-service.yaml
kubectl apply -f deployments/ops/elasticsearch-deployment.yaml
kubectl wait --for=condition=ready pod -l app=elasticsearch -n pharmago --timeout=300s

kubectl apply -f services/ops/
kubectl apply -f deployments/ops/

# 7. Backend services
kubectl apply -f services/backend/
kubectl apply -f deployments/backend/

# 8. Frontend
kubectl apply -f services/frontend/
kubectl apply -f deployments/frontend/
```

## Verificación

### Ver estado de los pods

```bash
# Ver todos los pods
kubectl get pods -n pharmago -o wide

# Ver pods de un nodo puntual
kubectl get pods -n pharmago -o wide --field-selector spec.nodeName=minikube-m02

# Verificar que cada microservicio de backend está en un nodo distinto
kubectl get pods -n pharmago -o wide -l tier=backend
```

### Ver servicios

```bash
kubectl get svc -n pharmago
```

### Ver logs

```bash
# Logs de un pod específico
kubectl logs -n pharmago <pod-name>

# Logs con seguimiento
kubectl logs -n pharmago -f <pod-name>
```

## Acceso a los Servicios

Hay dos opciones para acceder a los servicios: **port-forward** (recomendado en Windows) o **minikube service**.

### Opción 1: Port-forward (Recomendado en Windows)

En Windows, `localhost` puede fallar con `kubectl port-forward` y herramientas como `sqlcmd`. Usa **127.0.0.1** para todas las conexiones.

```bash
cd k8s
./port-forward.sh
```

Servicios disponibles en:
- **Frontend**: http://127.0.0.1:4200
- **API Gateway**: http://127.0.0.1:5000
- **BD (SQL Server)**: `127.0.0.1,11433` (sa / Str0ngP@ssword!)
- **Prometheus**: http://127.0.0.1:9090
- **Grafana**: http://127.0.0.1:3000 (admin/admin)
- **Kibana**: http://127.0.0.1:5601

Para detener: `./port-forward.sh --stop`

### Opción 2: Minikube service

### Frontend

```bash
minikube service pharmago-ui -n pharmago --url
```

### Grafana

```bash
minikube service grafana -n pharmago --url
# Credenciales: admin / admin
```

### Kibana

```bash
minikube service kibana -n pharmago --url
```

### Prometheus

```bash
minikube service prometheus -n pharmago --url
```

## Configuración de Replicas

Para cambiar el número de réplicas de cualquier componente, edita el archivo de deployment correspondiente:

```yaml
spec:
  replicas: 1  # Cambiar este valor
```

Luego aplica los cambios:

```bash
kubectl apply -f deployments/<component>/<deployment>.yaml
```

## Despliegues seguros (sin downtime)

**Requerimiento**: el sistema debe poder reemplazar sus componentes garantizando 100% de disponibilidad.

### Técnica elegida: Rolling Update

Los componentes propios (`pharmago-api-gateway`, `pharmago-users-service`, `pharmago-pharmacy-service` y `pharmago-ui`) se actualizan con la estrategia **RollingUpdate** de Kubernetes, configurada para que nunca haya cero réplicas disponibles:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # se permite 1 pod extra por encima de replicas durante el cambio
    maxUnavailable: 0  # nunca se baja un pod viejo antes de tener el nuevo READY
```

Secuencia de un reemplazo (con `replicas: 1`):

1. Se crea el pod con la versión nueva **al lado** del viejo, que sigue atendiendo todo el tráfico.
2. El pod nuevo pasa sus probes (`startupProbe` y luego `readinessProbe` contra `/health`). Recién ahí el Service lo agrega a sus endpoints y empieza a recibir tráfico.
3. Kubernetes marca el pod viejo para terminar y el Service lo quita de sus endpoints.
4. El hook `preStop` (`sleep 10`) retiene el apagado del pod viejo durante 10 segundos, para que kube-proxy en todos los nodos termine de dejar de enrutarle tráfico y para que los requests en curso terminen. Después el proceso recibe `SIGTERM` y se apaga (`terminationGracePeriodSeconds: 30`).

Si la versión nueva nunca llega a READY (no arranca, falla el health check, etc.), el pod viejo **sigue atendiendo**: el despliegue se queda esperando y el script `deploy` hace `kubectl rollout undo` automáticamente.

Piezas que lo hacen posible:

| Pieza | Para qué sirve |
|---|---|
| `strategy` con `maxSurge: 1` / `maxUnavailable: 0` | Siempre hay al menos una réplica atendiendo |
| `readinessProbe` (`/health`) | El tráfico solo llega a pods que están listos de verdad |
| `startupProbe` | Le da margen al arranque sin que la liveness lo mate |
| `lifecycle.preStop` + `terminationGracePeriodSeconds` | Apagado ordenado: sin requests cortados al bajar el pod viejo |
| Tags de imagen versionados (`<commit>` o `<commit>-dirty-<timestamp>`) | Cada despliegue es un cambio real y trazable de imagen, y se puede volver a cualquier versión |
| Anti-afinidad que excluye al propio servicio | Permite que versión nueva y vieja del mismo servicio convivan en un nodo durante el cambio, sin dejar que dos microservicios distintos compartan nodo |
| Afinidad obligatoria hacia el propio servicio | Todas las réplicas y los pods nuevos de un servicio van a su nodo, sin quitarle el nodo a otro microservicio |

#### Interacción con la anti-afinidad

Cada microservicio de backend debe correr en un nodo distinto. Con 3 nodos y 3 servicios, todos los nodos están ocupados, así que el pod nuevo de un servicio solo puede ir al nodo donde está **su propia** versión vieja. Por eso la regla es "ningún pod `tier=backend` de **otra** app en mi nodo":

```yaml
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchExpressions:
      - key: tier
        operator: In
        values: [backend]
      - key: app
        operator: NotIn
        values: [pharmago-users-service]   # el propio servicio
    topologyKey: kubernetes.io/hostname
```

Con la regla anterior (`tier=backend` a secas), el pod nuevo quedaba `Pending` para siempre y el despliegue nunca terminaba.

Además, todas las réplicas de un servicio se fuerzan al mismo nodo:

```yaml
podAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchLabels:
        app: pharmago-users-service
    topologyKey: kubernetes.io/hostname
```

Sin esta regla, al levantar el cluster de cero el scheduler podía mandar la segunda réplica de un servicio a un nodo vacío (por una anti-afinidad *preferida* entre réplicas, o por el spread que aplica por defecto). Por ejemplo: `api-gateway` en los nodos A y C y `users-service` en B deja a `pharmacy-service` sin nodo, en `Pending` para siempre. La primera réplica se puede ubicar aunque todavía no exista ningún pod del servicio (Kubernetes lo permite cuando el pod cumple su propio término), así que el scheduler sigue eligiendo el nodo.

Trade-off: como las réplicas comparten nodo, protegen ante la caída de un proceso o pod (lo que miden `inject-process-failure.sh` y `measure-mttr.sh`), pero no ante la caída del nodo. Con 3 nodos y un microservicio por nodo, no se pueden separar.

### Alternativas consideradas

- **Recreate**: baja todos los pods y después levanta los nuevos. Simple, pero hay downtime. Descartada.
- **Blue/Green**: dos Deployments completos (blue y green) y se cambia el selector del Service de uno al otro. Permite volver atrás al instante, pero duplica los recursos de todos los servicios y, con la restricción de un microservicio por nodo, necesitaría el doble de nodos. Descartada por costo.
- **Canary**: se manda un porcentaje del tráfico a la versión nueva. Requiere réplicas extra o un service mesh / ingress con pesos. Es más útil para validar versiones con usuarios reales que para garantizar disponibilidad. Descartada por complejidad.

Rolling update es nativo de Kubernetes, no requiere infraestructura adicional y, combinado con probes y `preStop`, garantiza que siempre haya una réplica sana atendiendo.

### Cómo desplegar una nueva versión

Desde `k8s/`:

```powershell
# Windows
.\build-images.ps1 -Services gateway   # construye con tag versionado y lo carga en Minikube
.\deploy.ps1 -Services gateway         # rolling update a esa versión
```

```bash
# Linux / Mac
./build-images.sh gateway
./deploy.sh gateway
```

Servicios válidos: `users`, `pharmacy`, `gateway`, `ui` (sin argumentos se usan todos).

- El tag se calcula con el hash corto del commit; si hay cambios sin commitear en `Backend/` o `Frontend/` se agrega `-dirty-<timestamp>`. Se guarda en `.image-tag`.
- `deploy` hace `kubectl set image`, espera con `kubectl rollout status` y, si falla, hace `kubectl rollout undo`.
- Historial y vuelta atrás:

  ```bash
  kubectl rollout history deployment/pharmago-api-gateway -n pharmago
  .\deploy.ps1 -Services gateway -Tag <tag-anterior>      # o: kubectl rollout undo deployment/pharmago-api-gateway -n pharmago
  ```

**Nota**: `apply-k8s` es para la instalación inicial (los manifiestos usan `:latest`). Para actualizar un cluster ya levantado usar `build-images` + `deploy`. Si se vuelve a correr `apply-k8s`, los deployments vuelven a `:latest` (también por rolling update, sin downtime).

### Cómo demostrarlo

`test-zero-downtime` levanta un pod con `curl` **dentro del cluster** que consulta en loop (cada ~0.2 s) los 4 Services y el camino gateway → users (`/test-health`, exento del rate limit) mientras corre el despliegue, y al final informa cuántas solicitudes fallaron:

```powershell
.\test-zero-downtime.ps1                     # despliega todo con el tag de .image-tag
.\test-zero-downtime.ps1 -Services gateway   # solo un servicio
.\test-zero-downtime.ps1 -Restart            # reemplaza los pods sin cambiar de imagen
```

```bash
./test-zero-downtime.sh
RESTART=1 ./test-zero-downtime.sh
```

Se mide desde adentro del cluster porque `kubectl port-forward` queda atado a un pod puntual y se corta cuando ese pod se reemplaza, lo que daría falsos negativos.

Resultado obtenido (cluster de 3 nodos, desplegando una nueva versión de los 4 componentes en secuencia):

```
=== Resultado ===
Ultimo conteo: STATS ok=1920 fail=0
0 solicitudes fallidas durante el despliegue: disponibilidad 100%
```

### Limitaciones

- **Base de datos**: `pharmago-db` (SQL Server) usa un volumen `ReadWriteOnce` y no admite dos instancias a la vez, por lo que su reemplazo implica un corte breve. El requerimiento se cumple para los microservicios y el frontend.
- **Componentes de observabilidad** (Prometheus, Grafana, Elasticsearch, Kibana): no forman parte del camino de atención a usuarios; se mantienen con su configuración actual.
- **Cambios en las reglas de anti-afinidad**: la anti-afinidad se evalúa también desde los pods existentes. Si se cambia la regla, los pods viejos (con la regla anterior) pueden bloquear a los nuevos; en ese caso hay que reemplazar los pods viejos de a uno (`kubectl delete pod ...`).

## Troubleshooting

### Pods no se inician (Pending)

Si algún pod queda en `Pending`:

1. **Falta etiqueta en los nodos**: frontend y ops requieren un nodo `node-type=all`; el backend, nodos `backend` o `all`.
   - Usa el script `apply-k8s.sh` / `apply-k8s.ps1` que etiqueta automáticamente, o
   - Manual: ver [Etiquetar nodos](#2-etiquetar-nodos)

   ```bash
   kubectl get nodes -L node-type
   ```

2. **Microservicios de backend en Pending con `didn't match pod anti-affinity rules`**: hay menos nodos aptos para backend que microservicios. Cada uno necesita su propio nodo: crear el cluster con `--nodes 3` (o `minikube node add`) y etiquetar el nodo nuevo con `node-type=backend`.

3. Verificar eventos del pod:
   ```bash
   kubectl describe pod <pod-name> -n pharmago
   ```

4. Ver logs:
   ```bash
   kubectl logs <pod-name> -n pharmago
   ```

### Imágenes no encontradas

Si los pods fallan con `ImagePullBackOff`:

1. Verificar que las imágenes están cargadas en Minikube:
   ```bash
   minikube image ls | grep pharmago
   ```

2. Si faltan imágenes, reconstruirlas y cargarlas:
   ```bash
   ./build-images.sh
   ```

3. Verificar que los deployments usan `imagePullPolicy: Never` (ya configurado).

### Base de datos no está lista

Si los servicios backend no pueden conectarse a la base de datos:

1. Verificar que el pod de la base de datos está corriendo:
   ```bash
   kubectl get pods -n pharmago -l app=pharmago-db
   ```

2. Verificar logs de la base de datos:
   ```bash
   kubectl logs -n pharmago -l app=pharmago-db
   ```

3. Verificar el secret:
   ```bash
   kubectl get secret db-secret -n pharmago -o yaml
   ```

### PersistentVolumes no se montan

En Minikube, los PersistentVolumes usan `hostPath` con `DirectoryOrCreate`, que crea los directorios automáticamente. Si tienes problemas:

```bash
# Conectarse al nodo y crear directorios manualmente
minikube ssh
sudo mkdir -p /mnt/data/{sql,elasticsearch,prometheus,grafana}
sudo chmod 777 /mnt/data/{sql,elasticsearch,prometheus,grafana}
exit
```

**Nota**: El deployment de SQL Server incluye un initContainer que configura los permisos para el usuario `mssql` (UID 10001).

### Elasticsearch OOMKilled (Out of Memory)

Si Elasticsearch está en `CrashLoopBackOff` con `OOMKilled`:

1. **Verificar memoria disponible en el nodo:**
   ```bash
   kubectl describe node minikube | grep -A 5 "Allocated resources"
   ```

2. **Aumentar memoria de Minikube:**
   ```bash
   minikube stop
   minikube delete
   minikube start --memory=6144 --cpus=4
   ```

3. **Reducir memoria heap de Elasticsearch:**
   Edita `deployments/ops/elasticsearch-deployment.yaml` y reduce `ES_JAVA_OPTS`:
   ```yaml
   - name: ES_JAVA_OPTS
     value: "-Xms1g -Xmx1g"  # Reducir de 2g a 1g
   ```
   Luego aumenta el límite de memoria del contenedor a 3-4Gi para compensar.

4. **Deshabilitar características que consumen memoria:**
   Agrega estas variables de entorno en el deployment:
   ```yaml
   - name: xpack.monitoring.collection.enabled
     value: "false"
   - name: xpack.security.enabled
     value: "false"  # Ya está configurado
   ```

5. **Verificar logs:**
   ```bash
   kubectl logs -n pharmago -l app=elasticsearch --tail=50
   ```

**Nota**: Elasticsearch requiere al menos 2GB de heap de Java y memoria adicional para el sistema operativo y otros procesos. En un entorno con recursos limitados (Minikube), considera usar una versión más ligera o deshabilitar características no esenciales.

### Kibana no está Ready

Si Kibana está `Running` pero no `Ready`:

1. **Verificar que Elasticsearch está funcionando:**
   ```bash
   kubectl get pods -n pharmago -l app=elasticsearch
   ```

2. **Verificar logs de Kibana:**
   ```bash
   kubectl logs -n pharmago -l app=kibana --tail=50
   ```

3. **Kibana espera a Elasticsearch:** Si Elasticsearch no está listo, Kibana no puede conectarse y permanecerá en `Running` pero no `Ready`.

## Limpieza (Equivalente a `docker-compose down`)

### Opción 1: Script automatizado (Recomendado)

```bash
cd k8s
chmod +x cleanup.sh
./cleanup.sh
```

**Conservar volúmenes persistentes:**
```bash
./cleanup.sh --keep-volumes
```

### Opción 2: Comando manual

```bash
# Eliminar namespace (elimina todos los recursos dentro de él)
kubectl delete namespace pharmago

# Eliminar PersistentVolumes (están fuera del namespace)
kubectl delete pv sql-pv elasticsearch-pv prometheus-pv grafana-pv
```

### Opción 3: Eliminar recursos individualmente

```bash
# Eliminar recursos en orden inverso al despliegue
kubectl delete -f deployments/
kubectl delete -f services/
kubectl delete -f configmaps/
kubectl delete -f secrets/
kubectl delete -f persistent-volumes/
kubectl delete -f namespace.yaml
```

**Nota**: Eliminar el namespace es la forma más simple y equivalente a `docker-compose down`, ya que elimina todos los recursos (pods, services, deployments, configmaps, secrets, PVCs) de una vez. Los PersistentVolumes deben eliminarse por separado ya que están fuera del namespace.

## Notas Importantes

1. **Logs**: Fluent Bit (DaemonSet) recolecta los logs de los pods y los envía directamente a Elasticsearch con índice `pharmago-logs-*`. Kibana se usa para visualizarlos.

2. **PersistentVolumes**: Los PVs usan `hostPath` que es adecuado para desarrollo pero no para producción. En producción, usa storage classes apropiadas.

3. **Secrets**: La contraseña de la base de datos está en texto plano en el secret. Para producción, considera usar herramientas como Sealed Secrets o external secret managers.

4. **Health Checks**: Los deployments incluyen health checks básicos. Asegúrate de que tus aplicaciones expongan endpoints `/health` o ajusta las configuraciones según corresponda.

5. **Recursos**: Los límites de recursos están configurados de forma conservadora. Ajusta según las necesidades de tu entorno.

## Estructura de Archivos

```
k8s/
├── namespace.yaml
├── configmaps/
│   ├── prometheus-config.yaml
│   ├── otel-collector-config.yaml
│   ├── grafana-provisioning.yaml
│   └── fluent-bit-config.yaml
├── secrets/
│   └── db-secret.yaml
├── persistent-volumes/
│   ├── sql-pv.yaml
│   ├── elasticsearch-pv.yaml
│   ├── prometheus-pv.yaml
│   └── grafana-pv.yaml
├── deployments/
│   ├── frontend/
│   │   └── ui-deployment.yaml
│   ├── backend/
│   │   ├── api-gateway-deployment.yaml
│   │   ├── users-service-deployment.yaml
│   │   └── pharmacy-service-deployment.yaml
│   └── ops/
│       ├── db-deployment.yaml
│       ├── otel-collector-deployment.yaml
│       ├── prometheus-deployment.yaml
│       ├── grafana-deployment.yaml
│       ├── elasticsearch-deployment.yaml
│       ├── kibana-deployment.yaml
│       └── fluent-bit-daemonset.yaml
├── services/
│   ├── frontend/
│   │   └── ui-service.yaml
│   ├── backend/
│   │   ├── api-gateway-service.yaml
│   │   ├── users-service-service.yaml
│   │   └── pharmacy-service-service.yaml
│   └── ops/
│       ├── db-service.yaml
│       ├── otel-collector-service.yaml
│       ├── prometheus-service.yaml
│       ├── grafana-service.yaml
│       ├── elasticsearch-service.yaml
│       └── kibana-service.yaml
├── build-images.sh / .ps1        # construye imágenes con tag versionado
├── deploy.sh / .ps1              # rolling update a una versión (con rollback automático)
├── test-zero-downtime.sh / .ps1  # prueba de disponibilidad durante un despliegue
├── apply-k8s.sh / .ps1           # instalación inicial
├── cleanup.sh / .ps1
└── README-k8s.md
```

