# Prueba de disponibilidad durante un despliegue
# Funciona en Windows PowerShell
# Uso:
#   .\test-zero-downtime.ps1                         # despliega todos con el tag de .image-tag
#   .\test-zero-downtime.ps1 -Services gateway       # solo algunos
#   .\test-zero-downtime.ps1 -Restart                # sin imagen nueva: kubectl rollout restart
#
# Levanta un pod con curl DENTRO del cluster que consulta en loop los Services
# (gateway, users, pharmacy, ui) y el camino gateway -> users (/test-health)
# mientras corre el despliegue, y al final informa cuantas solicitudes fallaron. Se prueba desde adentro porque un port-forward
# queda atado a un pod puntual y se corta en cada rollout.

param(
    [string[]]$Services = @("users", "pharmacy", "gateway", "ui"),
    [string]$Tag = "",
    [switch]$Restart
)

$namespace = "pharmago"
$probe = "zero-downtime-probe"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Cada iteracion consulta los 4 Services y gateway -> users (/test-health, exento del rate limit
# en appsettings.json); imprime cada falla y un resumen cada 20 iteraciones
# (sin comillas dobles: PowerShell 5.1 las rompe al pasar argumentos a kubectl)
$loop = @'
ok=0; fail=0; i=0
while true; do
  for u in http://pharmago-api-gateway/metrics http://pharmago-api-gateway/test-health http://pharmago-users-service/health http://pharmago-pharmacy-service/health http://pharmago-ui/; do
    c=$(curl -s -o /dev/null -m 3 -w '%{http_code}' $u)
    if [ x$c = x200 ]; then ok=$((ok+1)); else fail=$((fail+1)); echo $(date +%T) FAIL $c $u; fi
  done
  i=$((i+1)); [ $((i % 20)) -eq 0 ] && echo STATS ok=$ok fail=$fail
  sleep 0.2
done
'@

Write-Host "=== Prueba de disponibilidad durante el despliegue ===" -ForegroundColor Green
kubectl delete pod $probe -n $namespace --ignore-not-found=true --wait=true | Out-Null
kubectl run $probe -n $namespace --image=curlimages/curl:8.10.1 --restart=Never --command -- sh -c $loop | Out-Null
kubectl wait --for=condition=Ready "pod/$probe" -n $namespace --timeout=120s | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: el pod de prueba no arranco" -ForegroundColor Red
    exit 1
}
Write-Host "Pod de prueba consultando los Services. Esperando linea base..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

$deployments = @{
    "users" = "pharmago-users-service"; "pharmacy" = "pharmago-pharmacy-service"
    "gateway" = "pharmago-api-gateway"; "ui" = "pharmago-ui"
}
$deployExit = 0
if ($Restart) {
    foreach ($service in $Services) {
        kubectl rollout restart "deployment/$($deployments[$service])" -n $namespace
        kubectl rollout status "deployment/$($deployments[$service])" -n $namespace --timeout=300s
        if ($LASTEXITCODE -ne 0) { $deployExit = 1 }
    }
} else {
    $deployArgs = @{ Services = $Services }
    if (-not [string]::IsNullOrEmpty($Tag)) { $deployArgs.Tag = $Tag }
    & "$scriptDir\deploy.ps1" @deployArgs
    $deployExit = $LASTEXITCODE
}

# Dar tiempo a que terminen los pods viejos (preStop + apagado)
Write-Host "`nObservando 20s mas mientras terminan los pods viejos..." -ForegroundColor Cyan
Start-Sleep -Seconds 20

$logs = kubectl logs $probe -n $namespace
kubectl delete pod $probe -n $namespace --wait=false | Out-Null

$failures = @($logs | Where-Object { $_ -cmatch " FAIL " })
$stats = @($logs | Where-Object { $_ -match "^STATS" }) | Select-Object -Last 1

Write-Host "`n=== Resultado ===" -ForegroundColor Green
# Si el despliegue fallo se avisa primero: la disponibilidad puede ser 100% igual
# (los pods viejos siguieron atendiendo), pero la version nueva no quedo aplicada
if ($deployExit -ne 0) {
    Write-Host "DESPLIEGUE FALLIDO: la version nueva NO quedo aplicada (ver salida de arriba)" -ForegroundColor Red
    Write-Host "La disponibilidad de abajo corresponde al intento de despliegue" -ForegroundColor Yellow
}
Write-Host "Ultimo conteo: $stats"
if ($failures.Count -eq 0) {
    Write-Host "0 solicitudes fallidas durante el despliegue: disponibilidad 100%" -ForegroundColor Green
} else {
    Write-Host "$($failures.Count) solicitudes fallidas:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" }
}
if ($deployExit -ne 0) {
    exit 1
}
