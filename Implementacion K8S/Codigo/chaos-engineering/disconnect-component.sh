#!/bin/bash
# Baja un componente interno y lo vuelve a levantar. Uso: ./disconnect-component.sh [deployment] [segundos]
NS=pharmago
COMP="${1:-pharmago-db}"
SECS="${2:-60}"

echo "Bajando $COMP - $(date +%T)"
kubectl scale deployment $COMP -n $NS --replicas=0
sleep $SECS
echo "Levantando $COMP - $(date +%T)"
kubectl scale deployment $COMP -n $NS --replicas=1
kubectl rollout status deployment/$COMP -n $NS --timeout=180s
echo "$COMP de vuelta - $(date +%T)"