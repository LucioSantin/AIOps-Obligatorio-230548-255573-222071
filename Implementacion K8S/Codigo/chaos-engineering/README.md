# Chaos Engineering

Requiere: app en K8s + port-forward activo.

## Scripts

| Script | Uso | Que rompe |
|--------|-----|-----------|
| `load-requests.sh` | `bash load-requests.sh [cantidad] [url]` | Manda muchas requests al login |
| `cpu-spike.sh` | `bash cpu-spike.sh [deployment] [segundos]` | Pone la CPU de un pod al maximo |
| `ram-spike.sh` | `bash ram-spike.sh [deployment] [MB]` | Llena la memoria de un pod de a 10 MB por segundo |
| `volume-spike.sh` | `bash volume-spike.sh [deployment] [MB]` | Escribe un archivo grande en el disco del pod |
| `network-cut.sh` | `bash network-cut.sh [deployment] [segundos] [uno\|todos]` | Corta la red de un pod (o de todas las réplicas con `todos`) y despues la restaura |
| `disconnect-component.sh` | `bash disconnect-component.sh [deployment] [segundos]` | Baja un componente interno (por defecto la base) y lo vuelve a levantar |
| `circuit-breaker.sh` | `bash circuit-breaker.sh [red\|base] [segundos]` | Rompe pharmacy-service (corta su red o baja la base) y verifica que el gateway abra el circuito |
| `chaos-all.sh` | `bash chaos-all.sh` o `bash chaos-all.sh cpu` | Corre todos en orden, o uno solo (requests, cpu, memoria, disco, red, componente, breaker) |



Default deploy: pharmago-api-gateway

**Ver impacto en Grafana:** Dashboard "PharmaGo - Infra" → paneles "CPU por pod (pharmago)" y "Memoria por pod (pharmago)".

## Circuit breaker del API Gateway

El gateway tiene un circuit breaker por microservicio (cluster de YARP `users-cluster` y `pharmacy-cluster`), en `Backend/PharmaGo.ApiGateway/Resilience`. Evita que un servicio que está fallando reciba más tráfico y que los clientes se queden esperando timeouts.

- **Qué cuenta como falla:** respuestas 5xx y timeouts (el gateway corta a los 10 s sin actividad, `HttpRequest.ActivityTimeout` de cada cluster). Los 4xx **no cuentan**: son errores del cliente, y si contaran cualquiera podría abrir el circuito mandando requests inválidos.
- **Cuándo abre:** si en una ventana de 10 s hay al menos 10 requests y la mitad o más fallan.
- **Abierto:** durante 15 s el gateway responde `503` al instante, con los headers `Retry-After: 15` y `X-Circuit-Breaker: open`, sin llamar al microservicio.
- **Half-open:** pasados los 15 s deja pasar un request de prueba. Si sale bien el circuito se cierra; si falla, vuelve a abrir otros 15 s.
- Los parámetros están en la sección `CircuitBreaker` de `appsettings.json` del gateway.
- Cada réplica del gateway tiene su propio circuito (el estado está en memoria).
- **Observabilidad:** métrica `pharmago_circuit_breaker_state` (0 cerrado, 1 half-open, 2 abierto) por `cluster`, contador `pharmago_circuit_breaker_rejected_total`, alerta "Circuit breaker abierto" en Grafana y un log estructurado en cada cambio de estado (`"event":"circuit_breaker"` en Kibana).

Se complementa con el rate limit por IP del gateway: el rate limit acota cuántos requests puede mandar un solo cliente, y el circuit breaker protege al microservicio cuando igual empieza a fallar. El rate limit toma la IP de la conexión y no del header `X-Real-IP`, que un cliente podría falsificar para esquivarlo.

`circuit-breaker.sh` lo prueba: lanza 4 requests por segundo al gateway desde un pod del cluster, rompe pharmacy-service y al final muestra las respuestas por fase, cuándo abrió el circuito, la latencia de los rechazos y si se recuperó solo. Termina con `PASA` o `FALLA` (exit code 0 o 1). Hay que volver a construir y desplegar el gateway antes de correrlo.
