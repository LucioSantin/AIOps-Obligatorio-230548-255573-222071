#!/bin/bash
# Corre todos los experimentos de caos en orden. Uso: ./chaos-all.sh [requests|cpu|memoria|disco|red|componente|breaker]
cd "$(dirname "$0")"
PAUSA=60

requests()   { bash load-requests.sh 500; }
cpu()        { bash cpu-spike.sh pharmago-pharmacy-service 180; }
memoria()    { bash ram-spike.sh pharmago-pharmacy-service 270; }
disco()      { bash volume-spike.sh pharmago-pharmacy-service 200; }
red()        { bash network-cut.sh pharmago-users-service 60; }
componente() { bash disconnect-component.sh pharmago-db 60; }
breaker()    { bash circuit-breaker.sh red 40; }

correr() {
  echo ""
  echo "===== $1 - inicio $(date +%T)"
  $1
  echo "===== $1 - fin $(date +%T)"
}

if [ -n "$1" ]; then
  correr $1
  exit 0
fi

for t in requests cpu memoria disco red componente breaker; do
  correr $t
  echo "Esperando ${PAUSA}s para que se recupere..."
  sleep $PAUSA
done