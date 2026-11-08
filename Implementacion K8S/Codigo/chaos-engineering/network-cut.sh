#!/bin/bash
# Corta la red de un pod (o de todas las réplicas) unos segundos y la vuelve a poner.
# Uso: ./network-cut.sh [deployment] [segundos] [uno|todos]
#   uno   (por defecto) corta un solo pod: la otra réplica sigue atendiendo
#   todos corta todas las réplicas: el servicio queda inaccesible (dispara el circuit breaker del gateway)
NS=pharmago
DEPLOY="${1:-pharmago-users-service}"
SECS="${2:-30}"
ALCANCE="${3:-uno}"

case "$ALCANCE" in
  uno)   PODS=$(kubectl get pod -n $NS -l app=$DEPLOY -o jsonpath='{.items[0].metadata.name}') ;;
  todos) PODS=$(kubectl get pod -n $NS -l app=$DEPLOY -o jsonpath='{.items[*].metadata.name}') ;;
  *) echo "Uso: $0 [deployment] [segundos] [uno|todos]"; exit 1 ;;
esac
if [ -z "$PODS" ]; then echo "No hay pods con app=$DEPLOY en el namespace $NS"; exit 1; fi

# "nodo pid pod" de cada pod a cortar
OBJETIVOS=()
for POD in $PODS; do
  NODE=$(kubectl get pod $POD -n $NS -o jsonpath='{.spec.nodeName}')
  # PID del contenedor "pause" del pod, que es el dueño de la red del pod
  PID=$(minikube ssh -n $NODE -- "sudo crictl inspectp -o go-template --template '{{.info.pid}}' \$(sudo crictl pods --name $POD -q)" | tr -d '\r')
  if ! [[ "$PID" =~ ^[0-9]+$ ]]; then echo "No se pudo obtener el PID del pod $POD: $PID"; exit 1; fi
  OBJETIVOS+=("$NODE $PID $POD")
done

restaurar() {
  for o in "${OBJETIVOS[@]}"; do
    set -- $o
    minikube ssh -n $1 -- "sudo nsenter -t $2 -n iptables -D INPUT -j DROP; sudo nsenter -t $2 -n iptables -D OUTPUT -j DROP"
  done
  echo "Red restaurada $(date +%T)"
}
trap restaurar EXIT
trap 'exit 1' INT

for o in "${OBJETIVOS[@]}"; do
  set -- $o
  echo "Cortando red de $3 en $1 por ${SECS}s - $(date +%T)"
  minikube ssh -n $1 -- "sudo nsenter -t $2 -n iptables -I INPUT -j DROP && sudo nsenter -t $2 -n iptables -I OUTPUT -j DROP"
done
sleep $SECS
