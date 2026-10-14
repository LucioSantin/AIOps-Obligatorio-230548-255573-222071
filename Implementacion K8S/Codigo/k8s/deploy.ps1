# Despliegue seguro (rolling update sin downtime) de los componentes de PharmaGo
# Funciona en Windows PowerShell
# Uso:
#   .\deploy.ps1                          # despliega todos con el tag de .image-tag
#   .\deploy.ps1 -Services gateway        # solo algunos (users, pharmacy, gateway, ui)
#   .\deploy.ps1 -Tag 1a2b3c4             # tag explicito (ej: volver a una version anterior)
#
# Por cada servicio:
#   1. kubectl set image -> cambia la imagen del Deployment y dispara el rolling update
#      (maxSurge=1, maxUnavailable=0: el pod viejo sigue atendiendo hasta que el nuevo esta READY)
#   2. kubectl rollout status -> espera a que termine
#   3. Si el pod nuevo no llega a READY a tiempo, kubectl rollout undo -> vuelve a la version anterior
#
# Requiere haber corrido antes .\build-images.ps1 (carga las imagenes en Minikube).

param(
    [string[]]$Services = @("users", "pharmacy", "gateway", "ui"),
    [string]$Tag = "",
    [string]$Timeout = "300s"
)

$namespace = "pharmago"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrEmpty($Tag)) {
    if (-not (Test-Path "$scriptDir\.image-tag")) {
        Write-Host "Error: no hay .image-tag. Corre primero .\build-images.ps1 o pasa -Tag" -ForegroundColor Red
        exit 1
    }
    $Tag = (Get-Content "$scriptDir\.image-tag" -Raw).Trim()
}

# servicio -> Deployment (el contenedor y la imagen tienen el mismo nombre)
$catalog = @{
    "users"    = "pharmago-users-service"
    "pharmacy" = "pharmago-pharmacy-service"
    "gateway"  = "pharmago-api-gateway"
    "ui"       = "pharmago-ui"
}

Write-Host "=== Desplegando version $Tag ===" -ForegroundColor Green

foreach ($service in $Services) {
    if (-not $catalog.ContainsKey($service)) {
        Write-Host "Error: servicio desconocido '$service'. Validos: users, pharmacy, gateway, ui" -ForegroundColor Red
        exit 1
    }
    $deployment = $catalog[$service]

    Write-Host "`n- $deployment -> ${deployment}:$Tag" -ForegroundColor Cyan
    kubectl set image "deployment/$deployment" "$deployment=${deployment}:$Tag" -n $namespace
    if ($LASTEXITCODE -ne 0) { exit 1 }
    kubectl annotate "deployment/$deployment" "kubernetes.io/change-cause=deploy $Tag" --overwrite -n $namespace | Out-Null

    kubectl rollout status "deployment/$deployment" -n $namespace --timeout=$Timeout
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   El rollout de $deployment no termino en $Timeout. Volviendo a la version anterior..." -ForegroundColor Red
        kubectl rollout undo "deployment/$deployment" -n $namespace
        kubectl rollout status "deployment/$deployment" -n $namespace --timeout=$Timeout
        Write-Host "   Revisar: kubectl describe pod -n $namespace -l app=$deployment" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`n=== Despliegue completado (version $Tag) ===" -ForegroundColor Green
kubectl get pods -n $namespace -o wide
