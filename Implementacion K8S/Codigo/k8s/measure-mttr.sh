#!/bin/bash
# Borra un pod y mide cuánto tarda en volver a Ready. Uso ./measure-mttr.sh <users|pharmacy|gateway> [corridas]

NAMESPACE=pharmago
PROBE=mttr-probe
SERVICE="$1"
RUNS="${2:-3}"

case "$SERVICE" in
    users)    deployment=pharmago-users-service ;;
    pharmacy) deployment=pharmago-pharmacy-service ;;
    gateway)  deployment=pharmago-api-gateway ;;
    *) echo "Uso: $0 <users|pharmacy|gateway> [corridas]"; exit 1 ;;
esac

now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

# Pods Ready que no se están terminando, excluyendo el pod borrado
ready_pods() {
    kubectl get pods -n "$NAMESPACE" -l "app=$deployment" -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.deletionTimestamp} {.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
        | awk -v victim="$1" 'NF == 2 && $2 == "True" && $1 != victim' | wc -l | tr -d ' '
}

total_pods() {
    kubectl get pods -n "$NAMESPACE" -l "app=$deployment" --no-headers 2>/dev/null | wc -l | tr -d ' '
}

DESIRED="$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
echo "=== MTTR de $deployment ($DESIRED réplicas, $RUNS corridas) ==="

# Pod que consulta el Service cada 0,2 s e imprime cada falla
LOOP="
ok=0; fail=0
while true; do
  c=\$(curl -s -o /dev/null -m 2 -w '%{http_code}' http://$deployment/health)
  if [ \"\$c\" = \"200\" ]; then ok=\$((ok+1)); else fail=\$((fail+1)); echo \"\$(date +%T) FAIL \$c\"; fi
  echo \"STATS ok=\$ok fail=\$fail\" > /tmp/stats
  sleep 0.2
done
"
kubectl delete pod "$PROBE" -n "$NAMESPACE" --ignore-not-found=true --wait=true > /dev/null
kubectl run "$PROBE" -n "$NAMESPACE" --image=curlimages/curl:8.10.1 --restart=Never --command -- sh -c "$LOOP" > /dev/null
if ! kubectl wait --for=condition=Ready "pod/$PROBE" -n "$NAMESPACE" --timeout=120s > /dev/null; then
    echo "Error: el pod de prueba no arrancó"
    exit 1
fi
sleep 3

TIMES=()
for run in $(seq 1 "$RUNS"); do
    # Esperar a que no queden pods terminándose de la corrida anterior
    while [ "$(total_pods)" -ne "$DESIRED" ] || [ "$(ready_pods none)" -ne "$DESIRED" ]; do sleep 1; done

    victim="$(kubectl get pods -n "$NAMESPACE" -l "app=$deployment" -o jsonpath='{.items[0].metadata.name}')"
    start="$(now)"
    kubectl delete pod "$victim" -n "$NAMESPACE" --wait=false > /dev/null

    timeout_at=$(( ${start%.*} + 300 ))
    while [ "$(ready_pods "$victim")" -lt "$DESIRED" ]; do
        if [ "$(date +%s)" -gt "$timeout_at" ]; then
            echo "Corrida $run: no se recuperó en 300 s"
            break
        fi
        sleep 0.5
    done
    end="$(now)"
    secs="$(echo "$end - $start" | bc)"
    TIMES+=("$secs")
    echo "Corrida $run: borrado $victim, de nuevo $DESIRED/$DESIRED Ready en ${secs} s"
done

STATS="$(kubectl exec "$PROBE" -n "$NAMESPACE" -- cat /tmp/stats 2>/dev/null)"
FAILURES="$(kubectl logs "$PROBE" -n "$NAMESPACE" | grep ' FAIL ')"
kubectl delete pod "$PROBE" -n "$NAMESPACE" --wait=false > /dev/null

echo ""
echo "=== Resultado ==="
printf '%s\n' "${TIMES[@]}" | awk '{ s += $1; if (min == "" || $1 < min) min = $1; if ($1 > max) max = $1 }
    END { printf "MTTR del pod: promedio %.1f s, mínimo %.1f s, máximo %.1f s\n", s / NR, min, max }'
echo "Solicitudes al Service durante la prueba: $STATS"
if [ -n "$FAILURES" ]; then
    echo "Fallas:"
    echo "$FAILURES" | sed 's/^/  /'
fi
