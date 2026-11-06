# Chaos Engineering

Requiere: app en K8s + port-forward activo.

## Scripts

| Script | Uso | Que rompe |
|--------|-----|-----------|
| `load-requests.sh` | `bash load-requests.sh [cantidad] [url]` | Manda muchas requests al login |
| `cpu-spike.sh` | `bash cpu-spike.sh [deployment] [segundos]` | Pone la CPU de un pod al maximo |
| `ram-spike.sh` | `bash ram-spike.sh [deployment] [MB]` | Llena la memoria de un pod de a 10 MB por segundo |
| `volume-spike.sh` | `bash volume-spike.sh [deployment] [MB]` | Escribe un archivo grande en el disco del pod |
| `network-cut.sh` | `bash network-cut.sh [deployment] [segundos]` | Corta la red de un pod y despues la restaura |
| `disconnect-component.sh` | `bash disconnect-component.sh [deployment] [segundos]` | Baja un componente interno (por defecto la base) y lo vuelve a levantar |
| `chaos-all.sh` | `bash chaos-all.sh` o `bash chaos-all.sh cpu` | Corre todos en orden, o uno solo (requests, cpu, memoria, disco, red, componente) |



Default deploy: pharmago-api-gateway

**Ver impacto en Grafana:** Dashboard "PharmaGo - Infra" → paneles "CPU por pod (pharmago)" y "Memoria por pod (pharmago)".
