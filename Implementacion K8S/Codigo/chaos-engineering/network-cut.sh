#!/bin/bash
# Corta la red de un pod unos segundos y la vuelve a poner. Uso: ./network-cut.sh [deployment] [segundos]
NS=pharmago
DEPLOY="${1:-pharmago-users-service}"
SECS="${2:-30}"

POD=$(kubectl get pod -n $NS -l app=$DEPLOY -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl get pod $POD -n $NS -o jsonpath='{.spec.nodeName}')
# PID del contenedor "pause" del pod, que es el dueño de la red del pod
PID=$(minikube ssh -n $NODE -- "sudo crictl inspectp -o go-template --template '{{.info.pid}}' \$(sudo crictl pods --name $POD -q)" | tr -d '\r')
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then echo "No se pudo obtener el PID del pod: $PID"; exit 1; fi

restaurar() {
  minikube ssh -n $NODE -- "sudo nsenter -t $PID -n iptables -D INPUT -j DROP; sudo nsenter -t $PID -n iptables -D OUTPUT -j DROP"
  echo "Red restaurada $(date +%T)"
}
trap restaurar EXIT
trap 'exit 1' INT

echo "Cortando red de $POD en $NODE por ${SECS}s - $(date +%T)"
minikube ssh -n $NODE -- "sudo nsenter -t $PID -n iptables -I INPUT -j DROP && sudo nsenter -t $PID -n iptables -I OUTPUT -j DROP"
sleep $SECS