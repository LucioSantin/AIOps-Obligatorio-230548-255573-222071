#!/bin/bash
# Prueba de disponibilidad durante un despliegue
# Funciona en Linux y Mac
# Uso:
#   ./test-zero-downtime.sh                   # despliega todos con el tag de .image-tag
#   ./test-zero-downtime.sh gateway           # solo algunos
#   RESTART=1 ./test-zero-downtime.sh         # sin imagen nueva: kubectl rollout restart
#
# Levanta un pod con curl DENTRO del cluster que consulta en loop los Services
# (gateway, users, pharmacy, ui) y el camino gateway -> users (/test-health)
# mientras corre el despliegue, y al final informa cuántas solicitudes fallaron. Se prueba desde adentro porque un port-forward
# queda atado a un pod puntual y se corta en cada rollout.

NAMESPACE=pharmago
PROBE=zero-downtime-probe
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SERVICES=("$@")
if [ ${#SERVICES[@]} -eq 0 ]; then
    SERVICES=(users pharmacy gateway ui)
fi

# Cada iteración consulta los 4 Services y gateway -> users (/test-health, exento del rate limit
# en appsettings.json); imprime cada falla y un resumen cada 20 iteraciones
LOOP='
ok=0; fail=0; i=0
while true; do
  for u in http://pharmago-api-gateway/metrics http://pharmago-api-gateway/test-health http://pharmago-users-service/health http://pharmago-pharmacy-service/health http://pharmago-ui/; do
    c=$(curl -s -o /dev/null -m 3 -w "%{http_code}" "$u")
    if [ "$c" = "200" ]; then ok=$((ok+1)); else fail=$((fail+1)); echo "$(date +%T) FAIL $c $u"; fi
  done
  i=$((i+1)); [ $((i % 20)) -eq 0 ] && echo "STATS ok=$ok fail=$fail"
  sleep 0.2
done
'

echo "=== Prueba de disponibilidad durante el despliegue ==="
kubectl delete pod "$PROBE" -n "$NAMESPACE" --ignore-not-found=true --wait=true > /dev/null
kubectl run "$PROBE" -n "$NAMESPACE" --image=curlimages/curl:8.10.1 --restart=Never --command -- sh -c "$LOOP" > /dev/null
if ! kubectl wait --for=condition=Ready "pod/$PROBE" -n "$NAMESPACE" --timeout=120s > /dev/null; then
    echo "Error: el pod de prueba no arrancó"
    exit 1
fi
echo "Pod de prueba consultando los Services. Esperando línea base..."
sleep 10

DEPLOY_EXIT=0
if [ -n "$RESTART" ]; then
    for service in "${SERVICES[@]}"; do
        case "$service" in
            users)    deployment=pharmago-users-service ;;
            pharmacy) deployment=pharmago-pharmacy-service ;;
            gateway)  deployment=pharmago-api-gateway ;;
            ui)       deployment=pharmago-ui ;;
        esac
        kubectl rollout restart "deployment/$deployment" -n "$NAMESPACE"
        kubectl rollout status "deployment/$deployment" -n "$NAMESPACE" --timeout=300s || DEPLOY_EXIT=1
    done
else
    "$SCRIPT_DIR/deploy.sh" "${SERVICES[@]}" || DEPLOY_EXIT=1
fi

# Dar tiempo a que terminen los pods viejos (preStop + apagado)
echo ""
echo "Observando 20s más mientras terminan los pods viejos..."
sleep 20

LOGS="$(kubectl logs "$PROBE" -n "$NAMESPACE")"
kubectl delete pod "$PROBE" -n "$NAMESPACE" --wait=false > /dev/null

FAILURES="$(echo "$LOGS" | grep ' FAIL ')"
STATS="$(echo "$LOGS" | grep '^STATS' | tail -1)"

echo ""
echo "=== Resultado ==="
# Si el despliegue falló se avisa primero: la disponibilidad puede ser 100% igual
# (los pods viejos siguieron atendiendo), pero la versión nueva no quedó aplicada
if [ "$DEPLOY_EXIT" -ne 0 ]; then
    echo "DESPLIEGUE FALLIDO: la versión nueva NO quedó aplicada (ver salida de arriba)"
    echo "La disponibilidad de abajo corresponde al intento de despliegue"
fi
echo "Último conteo: $STATS"
if [ -z "$FAILURES" ]; then
    echo "0 solicitudes fallidas durante el despliegue: disponibilidad 100%"
else
    echo "$(echo "$FAILURES" | wc -l) solicitudes fallidas:"
    echo "$FAILURES" | sed 's/^/  /'
fi
if [ "$DEPLOY_EXIT" -ne 0 ]; then
    exit 1
fi
