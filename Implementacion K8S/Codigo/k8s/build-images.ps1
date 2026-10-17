# Script para construir y cargar imágenes Docker en Minikube (multi-nodo)
# Funciona en Windows PowerShell
# Uso:
#   .\build-images.ps1                          # construye todas las imagenes
#   .\build-images.ps1 -Services gateway,users  # solo algunas (users, pharmacy, gateway, ui)
#   .\build-images.ps1 -Tag v2                  # tag explicito
#
# Cada imagen se etiqueta con una version unica (hash corto del commit, con
# sufijo -dirty-<timestamp> si hay cambios sin commitear en Backend/Frontend)
# y ademas con :latest (usado por los manifiestos en la instalacion inicial).
# El tag generado se guarda en .image-tag para que deploy.ps1 lo use.

param(
    [string[]]$Services = @("users", "pharmacy", "gateway", "ui"),
    [string]$Tag = ""
)

Write-Host "=== Construyendo y cargando imagenes Docker en Minikube ===" -ForegroundColor Green

# Verificar que docker está disponible
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Error: Docker no esta instalado o no esta en el PATH" -ForegroundColor Red
    exit 1
}

# Verificar que minikube está corriendo
$minikubeStatus = minikube status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Minikube no esta corriendo. Ejecuta: minikube start --nodes 3" -ForegroundColor Red
    exit 1
}

# Obtener el directorio base (donde está este script)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$codeDir = Split-Path -Parent $scriptDir

# Calcular el tag de la version
if ([string]::IsNullOrEmpty($Tag)) {
    $Tag = (git -C $codeDir rev-parse --short HEAD).Trim()
    $changes = git -C $codeDir status --porcelain -- Backend Frontend
    if (-not [string]::IsNullOrEmpty($changes)) {
        $Tag = "$Tag-dirty-$(Get-Date -Format 'yyyyMMddHHmmss')"
    }
}
Write-Host "Tag de version: $Tag" -ForegroundColor Cyan

# servicio -> imagen, directorio de contexto y Dockerfile
$catalog = @{
    "users"    = @{ Image = "pharmago-users-service";    Context = "Backend";  Dockerfile = "PharmaGo.UsersService/Dockerfile" }
    "pharmacy" = @{ Image = "pharmago-pharmacy-service"; Context = "Backend";  Dockerfile = "PharmaGo.PharmacyService/Dockerfile" }
    "gateway"  = @{ Image = "pharmago-api-gateway";      Context = "Backend";  Dockerfile = "PharmaGo.ApiGateway/Dockerfile" }
    "ui"       = @{ Image = "pharmago-ui";               Context = "Frontend"; Dockerfile = "Dockerfile" }
}

foreach ($service in $Services) {
    if (-not $catalog.ContainsKey($service)) {
        Write-Host "Error: servicio desconocido '$service'. Validos: users, pharmacy, gateway, ui" -ForegroundColor Red
        exit 1
    }
    $entry = $catalog[$service]
    $image = $entry.Image

    Write-Host "`n  - ${image}:$Tag..." -ForegroundColor Cyan
    Set-Location "$codeDir\$($entry.Context)"
    docker build -f $entry.Dockerfile -t "${image}:$Tag" -t "${image}:latest" .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error construyendo $image" -ForegroundColor Red
        Set-Location $scriptDir
        exit 1
    }
    minikube image load "${image}:$Tag"
    minikube image load "${image}:latest"
}

Set-Location $scriptDir
Set-Content -Path "$scriptDir\.image-tag" -Value $Tag -NoNewline

Write-Host "`n=== Imagenes construidas y cargadas exitosamente (tag: $Tag) ===" -ForegroundColor Green
Write-Host "Para desplegarlas sin downtime: .\deploy.ps1 -Services $($Services -join ',')" -ForegroundColor White
Write-Host "`nVerificando imagenes en Minikube..." -ForegroundColor Yellow
minikube image ls | Select-String "pharmago"
