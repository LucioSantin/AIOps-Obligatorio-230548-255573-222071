#!/bin/sh
# Chaos: RAM spike en pod. Uso: ./ram-spike.sh [deployment] [MB]
DEPLOY="${1:-pharmago-api-gateway}"
MB="${2:-200}"
POD=$(kubectl get pod -n pharmago -l app="$DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
  echo "Error: no hay pods con app=$DEPLOY en el namespace pharmago."
  exit 1
fi
echo "RAM spike: $POD (${MB}MB)"
kubectl exec -n pharmago "$POD" -- sh -c 'i=0; while [ $i -lt '"$MB"' ]; do i=$((i+10)); eval "v$i=\$(head -c 10M /dev/zero | tr \"\\000\" a)"; sleep 1; done; sleep 90'