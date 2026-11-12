# Script de despliegue para Kubernetes (Minikube)
# Uso: .\apply-k8s.ps1

Write-Host "=== Desplegando PharmaGo en Kubernetes ===" -ForegroundColor Green

# Verificar que kubectl está disponible
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "Error: kubectl no está instalado o no está en el PATH" -ForegroundColor Red
    exit 1
}

# Verificar que el cluster Kubernetes está accesible
$nodes = kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($nodes)) {
    Write-Host "Error: No hay cluster Kubernetes accesible. Si usas Minikube: minikube start --nodes 3 --memory=6144 --cpus=4" -ForegroundColor Red
    exit 1
}

# Etiquetar nodos (requerido para que los pods se programen)
# El primer nodo aloja frontend, ops y un microservicio de backend (node-type=all);
# el resto quedan para backend. Cada microservicio de backend necesita su propio
# nodo (anti-afinidad), así que con 3 microservicios hacen falta 3 nodos.
Write-Host "`n1. Etiquetando nodos..." -ForegroundColor Yellow
$nodeList = $nodes.Trim().Split(" ", [StringSplitOptions]::RemoveEmptyEntries)
kubectl label nodes $nodeList[0] node-type=all --overwrite | Out-Null
Write-Host "   $($nodeList[0]) -> node-type=all" -ForegroundColor Cyan
foreach ($node in ($nodeList | Select-Object -Skip 1)) {
    kubectl label nodes $node node-type=backend --overwrite | Out-Null
    Write-Host "   $node -> node-type=backend" -ForegroundColor Cyan
}
if ($nodeList.Count -lt 3) {
    Write-Host "   Atencion: hay $($nodeList.Count) nodo(s). Los microservicios de backend necesitan uno cada uno: minikube start --nodes 3" -ForegroundColor Yellow
}
Write-Host "   Verificar: kubectl get nodes --show-labels" -ForegroundColor Gray

Write-Host "`n2. Creando namespace..." -ForegroundColor Yellow
kubectl apply -f namespace.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n3. Creando secrets..." -ForegroundColor Yellow
kubectl apply -f secrets\db-secret.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n4. Creando configmaps..." -ForegroundColor Yellow
# Prometheus, el collector y Grafana montan sus ConfigMaps con subPath (no ven los cambios) y
# Fluent Bit no recarga su config: si un ConfigMap cambio, se reinicia a quien lo usa en el paso 11
$restart = @()
function Set-ConfigMap($file, $target) {
    $out = kubectl apply -f $file
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Write-Host $out
    if ($out -match ' configured$') { $script:restart += $target }
}
Set-ConfigMap configmaps\prometheus-config.yaml       deployment/prometheus
Set-ConfigMap configmaps\otel-collector-config.yaml   deployment/otlp-collector
Set-ConfigMap configmaps\grafana-provisioning.yaml    deployment/grafana
Set-ConfigMap configmaps\grafana-dashboards.yaml      deployment/grafana
Set-ConfigMap configmaps\grafana-dashboard-infra.yaml deployment/grafana
Set-ConfigMap configmaps\fluent-bit-config.yaml       daemonset/fluent-bit
Set-ConfigMap configmaps\grafana-alerting.yaml        deployment/grafana

Write-Host "`n5. Creando StorageClass y PersistentVolumes..." -ForegroundColor Yellow
kubectl apply -f persistent-volumes\storage-class.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

# Eliminar solo PVs en estado Released (huerfanos tras borrar el namespace).
# No intentar borrar PVs Bound: kubectl delete se bloquearia indefinidamente.
Write-Host "   Limpiando PVs huerfanos (Released)..." -ForegroundColor Cyan
foreach ($pv in @("sql-pv", "sql-backup-pv", "elasticsearch-pv", "prometheus-pv", "grafana-pv")) {
    $status = kubectl get pv $pv -o jsonpath='{.status.phase}' 2>$null
    if ($status -eq "Released" -or $status -eq "Failed") {
        kubectl delete pv $pv --ignore-not-found=true
    }
}
Start-Sleep -Seconds 2

kubectl apply -f persistent-volumes\sql-pv.yaml
kubectl apply -f persistent-volumes\sql-backup-pv.yaml
kubectl apply -f persistent-volumes\elasticsearch-pv.yaml
kubectl apply -f persistent-volumes\prometheus-pv.yaml
kubectl apply -f persistent-volumes\grafana-pv.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n6. Desplegando base de datos..." -ForegroundColor Yellow
kubectl apply -f services\ops\db-service.yaml
kubectl apply -f deployments\ops\db-deployment.yaml
kubectl apply -f cronjobs\db-backup-cronjob.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n   Esperando a que la base de datos esté lista..." -ForegroundColor Yellow
# Esperar a que el pod esté Ready
$timeout = 0
$maxTimeout = 300
do {
    # Comillas simples adentro del filtro: Windows PowerShell 5.1 borra las comillas dobles
    # internas al llamar a kubectl, el filtro queda invalido y el loop esperaba siempre los 300 s
    $podReady = kubectl get pod -l app=pharmago-db -n pharmago -o jsonpath="{.items[0].status.conditions[?(@.type=='Ready')].status}" 2>&1
    if ($podReady -eq "True") {
        Write-Host "   Base de datos lista!" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 5
    $timeout += 5
    if ($timeout -ge $maxTimeout) {
        Write-Host "   Timeout esperando la base de datos. Continuando..." -ForegroundColor Yellow
        break
    }
    Write-Host "   Esperando... ($timeout/$maxTimeout segundos)" -ForegroundColor Cyan
} while ($true)

Write-Host "`n7. Desplegando servicios de observabilidad..." -ForegroundColor Yellow
# Elasticsearch
kubectl apply -f services\ops\elasticsearch-service.yaml
kubectl apply -f deployments\ops\elasticsearch-deployment.yaml

Write-Host "   Esperando a que Elasticsearch esté listo..." -ForegroundColor Yellow
$timeout = 0
$maxTimeout = 300
do {
    $podReady = kubectl get pod -l app=elasticsearch -n pharmago -o jsonpath="{.items[0].status.conditions[?(@.type=='Ready')].status}" 2>&1
    if ($podReady -eq "True") {
        Write-Host "   Elasticsearch listo!" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 5
    $timeout += 5
    if ($timeout -ge $maxTimeout) {
        Write-Host "   Timeout esperando Elasticsearch. Continuando..." -ForegroundColor Yellow
        break
    }
    Write-Host "   Esperando... ($timeout/$maxTimeout segundos)" -ForegroundColor Cyan
} while ($true)

# Resto de servicios ops
kubectl apply -f deployments\ops\prometheus-serviceaccount.yaml
kubectl apply -f deployments\ops\prometheus-clusterrole.yaml
kubectl apply -f deployments\ops\prometheus-clusterrolebinding.yaml
kubectl apply -f services\ops\otel-collector-service.yaml
kubectl apply -f deployments\ops\otel-collector-deployment.yaml
kubectl apply -f services\ops\jaeger-service.yaml
kubectl apply -f deployments\ops\jaeger-deployment.yaml

kubectl apply -f services\ops\prometheus-service.yaml
kubectl apply -f deployments\ops\prometheus-deployment.yaml
kubectl apply -f services\ops\node-exporter-service.yaml
kubectl apply -f deployments\ops\node-exporter-daemonset.yaml
kubectl apply -f services\ops\kube-state-metrics-service.yaml
kubectl apply -f deployments\ops\kube-state-metrics.yaml

kubectl apply -f services\ops\grafana-service.yaml
kubectl apply -f deployments\ops\grafana-deployment.yaml

kubectl apply -f services\ops\kibana-service.yaml
kubectl apply -f deployments\ops\kibana-deployment.yaml

if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n8. Desplegando servicios backend..." -ForegroundColor Yellow
kubectl apply -f services\backend\users-service-service.yaml
kubectl apply -f deployments\backend\users-service-deployment.yaml

kubectl apply -f services\backend\pharmacy-service-service.yaml
kubectl apply -f deployments\backend\pharmacy-service-deployment.yaml

kubectl apply -f services\backend\api-gateway-service.yaml
kubectl apply -f deployments\backend\api-gateway-deployment.yaml

if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n9. Desplegando frontend..." -ForegroundColor Yellow
kubectl apply -f services\frontend\ui-service.yaml
kubectl apply -f deployments\frontend\ui-deployment.yaml

Write-Host "`n10. Creando PodDisruptionBudgets..." -ForegroundColor Yellow
kubectl apply -f pdb\pharmago-pdbs.yaml

if ($LASTEXITCODE -ne 0) { exit 1 }

if ($restart.Count -gt 0) {
    Write-Host "`n11. Reiniciando componentes con config nueva..." -ForegroundColor Yellow
    foreach ($target in ($restart | Sort-Object -Unique)) {
        kubectl rollout restart $target -n pharmago
        kubectl rollout status $target -n pharmago --timeout=300s
    }
}

Write-Host "`n=== Despliegue completado ===" -ForegroundColor Green
Write-Host "`nVerificando estado de los pods..." -ForegroundColor Yellow
kubectl get pods -n pharmago -o wide

Write-Host "`nPara ver los servicios expuestos:" -ForegroundColor Cyan
Write-Host "  Frontend:     minikube service pharmago-ui -n pharmago --url" -ForegroundColor White
Write-Host "  Grafana:      minikube service grafana -n pharmago --url" -ForegroundColor White
Write-Host "  Kibana:       minikube service kibana -n pharmago --url" -ForegroundColor White
Write-Host "  Prometheus:   minikube service prometheus -n pharmago --url" -ForegroundColor White
