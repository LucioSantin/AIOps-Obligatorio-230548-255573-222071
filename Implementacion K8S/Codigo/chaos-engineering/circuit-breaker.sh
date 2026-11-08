#!/bin/bash
# Rompe pharmacy-service y verifica que el circuit breaker del gateway corte el tráfico:
# con el circuito abierto el gateway tiene que responder 503 al instante en vez de esperar timeouts,
# y cuando el servicio vuelve el circuito se tiene que cerrar solo.
# Uso: ./circuit-breaker.sh [red|base] [segundos]
#   red  (por defecto) corta la red de todas las réplicas de pharmacy-service (requests colgados)
#   base baja la base de datos (pharmacy-service responde errores y queda sin réplicas READY)
cd "$(dirname "$0")"
NS=pharmago
PROBE=breaker-probe
MODO="${1:-red}"
SECS="${2:-40}"
URL="http://pharmago-api-gateway/api/drug"
# Latencia máxima aceptable de un rechazo del circuito
MAX_RECHAZO=0.5
INICIO=$(date +%s)

case "$MODO" in
  red)  falla() { bash network-cut.sh pharmago-pharmacy-service "$SECS" todos; } ;;
  base) falla() { bash disconnect-component.sh pharmago-db "$SECS"; } ;;
  *) echo "Uso: $0 [red|base] [segundos]"; exit 1 ;;
esac

# Pod que lanza un request al gateway cada 0,25 s sin esperar la respuesta anterior (así un request
# colgado no frena a los demás) y anota: segundo de inicio, código, latencia y header X-Circuit-Breaker.
# 4 req/s queda debajo del rate limit de 300 por minuto.
LOOP="
while true; do
  ( t=\$(date +%s); r=\$(curl -s -o /dev/null -m 15 -w '%{http_code} %{time_total} %header{x-circuit-breaker}' $URL); echo \"\$t \$r\" >> /tmp/log ) &
  sleep 0.25
done
"
kubectl delete pod $PROBE -n $NS --ignore-not-found=true --wait=true > /dev/null
kubectl run $PROBE -n $NS --image=curlimages/curl:8.10.1 --restart=Never --command -- sh -c "$LOOP" > /dev/null
if ! kubectl wait --for=condition=Ready pod/$PROBE -n $NS --timeout=120s > /dev/null; then
  echo "Error: el pod de prueba no arrancó"
  exit 1
fi
# Los tiempos se toman con el reloj del pod, el mismo que usa el log
reloj() { kubectl exec $PROBE -n $NS -- date +%s | tr -d '\r'; }
ok_desde() { kubectl exec $PROBE -n $NS -- sh -c "awk '\$1 >= $1 && \$2 == 200' /tmp/log | wc -l" | tr -d ' \r'; }

echo "Midiendo 10 s sin fallas - $(date +%T)"
sleep 10

T_FALLA=$(reloj)
echo "===== Inyectando falla ($MODO, ${SECS}s) - $(date +%T)"
falla
T_RESTAURA=$(reloj)

echo "===== Falla restaurada, esperando que el circuito se cierre - $(date +%T)"
# La base tarda en volver (SQL Server arranca y pharmacy-service tiene que pasar la readiness)
for i in $(seq 1 90); do
  [ "$(ok_desde "$T_RESTAURA")" -ge 8 ] && break
  sleep 2
done
sleep 5

LOG=$(mktemp)
kubectl exec $PROBE -n $NS -- cat /tmp/log > "$LOG"
kubectl delete pod $PROBE -n $NS --wait=false > /dev/null

echo ""
echo "===== Cambios de estado del circuito (logs del gateway, cada réplica tiene su circuito)"
kubectl logs -n $NS -l app=pharmago-api-gateway --since=$(( $(date +%s) - INICIO + 5 ))s --prefix --timestamps 2>/dev/null \
  | grep '"Message":"Circuito' \
  | sed -E 's/^\[pod\/([^/]*)\/[^]]*\] ([0-9T:-]*)\.[^ ]* .*"Message":"([^"]*)".*/  \2  \1  \3/; s/ correlation_id=[a-f0-9]*//' \
  | sed 's/\\u00E1/á/g; s/\\u00F3/ó/g' \
  | sort

echo ""
echo "===== Respuestas del gateway por fase"
awk -v falla="$T_FALLA" -v restaura="$T_RESTAURA" '{
    fase = ($1 < falla) ? "1 antes  " : ($1 < restaura) ? "2 durante" : "3 después"
    n[fase "  " $2 ($4 == "open" ? " (circuito abierto)" : "")]++
  }
  END { for (k in n) printf "  %s x%d\n", k, n[k] }' "$LOG" | sort | sed 's/^  [0-9] /  /'

echo ""
echo "===== Resultado"
awk -v falla="$T_FALLA" -v restaura="$T_RESTAURA" -v max_rechazo="$MAX_RECHAZO" '
  {
    t = $1; code = $2; lat = $3 + 0
    if ($4 == "open") {
      rechazos++; suma += lat; if (lat > max_abierto) max_abierto = lat
      if (primer_abierto == "" || t < primer_abierto) primer_abierto = t
    } else if (t >= falla && code != 200) {
      if (lat > max_lenta) max_lenta = lat
      if (lat > 1) lentas++
    }
    if (t >= restaura && code == 200 && (primer_ok == "" || t < primer_ok)) primer_ok = t
  }
  END {
    printf "  Fallas lentas antes de abrir (más de 1 s): %d, la más lenta %.2f s\n", lentas, max_lenta
    if (rechazos > 0) {
      printf "  El circuito abrió a los %d s de la falla\n", primer_abierto - falla
      printf "  Rechazos con circuito abierto: %d, latencia promedio %.3f s, máxima %.3f s\n", rechazos, suma / rechazos, max_abierto
    } else print "  El circuito no abrió"
    if (primer_ok != "") printf "  Volvió a responder 200 a los %d s de restaurar la falla\n", primer_ok - restaura
    else print "  No volvió a responder 200"

    abrio = rechazos > 0; rapido = max_abierto < max_rechazo; volvio = primer_ok != ""
    print ""
    if (abrio && rapido && volvio) print "PASA: el gateway cortó el tráfico respondiendo 503 al instante y se recuperó solo"
    else {
      if (!abrio)  print "FALLA: el circuito no abrió"
      if (abrio && !rapido) printf "FALLA: los rechazos tardaron más de %s s\n", max_rechazo
      if (!volvio) print "FALLA: el servicio no volvió a responder 200"
    }
    exit (abrio && rapido && volvio) ? 0 : 1
  }' "$LOG"
RESULT=$?
rm -f "$LOG"
exit $RESULT
