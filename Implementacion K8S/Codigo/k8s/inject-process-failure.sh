#!/bin/bash
# Mata (crash) o congela (hang) el proceso de un pod y mide cuánto tarda en recuperarse. Uso ./inject-process-failure.sh <users|pharmacy|gateway> [crash|hang]

NAMESPACE=pharmago
PROBE=failure-probe
SERVICE="$1"
MODE="${2:-crash}"

case "$SERVICE" in
    users)    deployment=pharmago-users-service ;;
    pharmacy) deployment=pharmago-pharmacy-service ;;
    gateway)  deployment=pharmago-api-gateway ;;
    *) echo "Uso: $0 <users|pharmacy|gateway> [crash|hang]"; exit 1 ;;
esac

case "$MODE" in
    crash) SIGNAL=KILL ;;
    hang)  SIGNAL=STOP ;;
    *) echo "Uso: $0 <users|pharmacy|gateway> [crash|hang]"; exit 1 ;;
esac

now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

pod_field() {
    kubectl get pod "$victim" -n "$NAMESPACE" -o jsonpath="$1"
}

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

victim="$(kubectl get pods -n "$NAMESPACE" -l "app=$deployment" -o jsonpath='{.items[0].metadata.name}')"
node="$(pod_field '{.spec.nodeName}')"
restarts="$(pod_field '{.status.containerStatuses[0].restartCount}')"
container_id="$(pod_field '{.status.containerStatuses[0].containerID}')"

# PID del proceso visto desde el nodo, según el runtime del clúster
case "$container_id" in
    docker://*)     pid="$(minikube ssh -n "$node" -- "docker inspect -f '{{.State.Pid}}' ${container_id#docker://}" | tr -d '\r')" ;;
    containerd://*) pid="$(minikube ssh -n "$node" -- "sudo crictl inspect -o go-template --template '{{.info.pid}}' ${container_id#containerd://}" | tr -d '\r')" ;;
    *) echo "Error: runtime no soportado ($container_id)"; exit 1 ;;
esac

echo "Pod $victim en $node, proceso $pid, señal $SIGNAL, reinicios previos $restarts"
start="$(now)"
# Desde el nodo porque dentro del contenedor la app es PID 1 y el kernel ignora KILL/STOP
minikube ssh -n "$node" -- "sudo kill -$SIGNAL $pid"

# Espera a que la readinessProbe lo saque del Service
while [ "$(pod_field '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ]; do sleep 0.2; done
echo "Fuera del Service a los $(echo "$(now) - $start" | bc) s"

# Espera a que el contenedor se reinicie y vuelva a estar Ready
timeout_at=$(( ${start%.*} + 300 ))
while [ "$(pod_field '{.status.containerStatuses[0].restartCount}')" -le "$restarts" ] \
    || [ "$(pod_field '{.status.conditions[?(@.type=="Ready")].status}')" != "True" ]; do
    if [ "$(date +%s)" -gt "$timeout_at" ]; then
        echo "No se recuperó en 300 s"
        break
    fi
    sleep 0.5
done
echo "Contenedor reiniciado y Ready de nuevo a los $(echo "$(now) - $start" | bc) s (reinicios $(pod_field '{.status.containerStatuses[0].restartCount}'))"
echo "Motivo del reinicio $(pod_field '{.status.containerStatuses[0].lastState.terminated.reason}') (exit $(pod_field '{.status.containerStatuses[0].lastState.terminated.exitCode}'))"

STATS="$(kubectl exec "$PROBE" -n "$NAMESPACE" -- cat /tmp/stats 2>/dev/null)"
FAILURES="$(kubectl logs "$PROBE" -n "$NAMESPACE" | grep ' FAIL ')"
kubectl delete pod "$PROBE" -n "$NAMESPACE" --wait=false > /dev/null

echo "Solicitudes al Service ${STATS#STATS }"
if [ -n "$FAILURES" ]; then
    echo "$FAILURES" | sed 's/^/  /'
fi
