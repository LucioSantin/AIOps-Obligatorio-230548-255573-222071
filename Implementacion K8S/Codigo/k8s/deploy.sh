#!/bin/bash
# Despliegue seguro (rolling update sin downtime) de los componentes de PharmaGo
# Funciona en Linux y Mac
# Uso:
#   ./deploy.sh                       # despliega todos con el tag de .image-tag
#   ./deploy.sh gateway               # solo algunos (users, pharmacy, gateway, ui)
#   TAG=1a2b3c4 ./deploy.sh           # tag explícito (ej: volver a una versión anterior)
#
# Por cada servicio:
#   1. kubectl set image -> cambia la imagen del Deployment y dispara el rolling update
#      (maxSurge=1, maxUnavailable=0: el pod viejo sigue atendiendo hasta que el nuevo está READY)
#   2. kubectl rollout status -> espera a que termine
#   3. Si el pod nuevo no llega a READY a tiempo, kubectl rollout undo -> vuelve a la versión anterior
#
# Requiere haber corrido antes ./build-images.sh (carga las imágenes en Minikube).

set -e

NAMESPACE=pharmago
TIMEOUT="${TIMEOUT:-300s}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$TAG" ]; then
    if [ ! -f "$SCRIPT_DIR/.image-tag" ]; then
        echo "Error: no hay .image-tag. Corre primero ./build-images.sh o define TAG"
        exit 1
    fi
    TAG="$(cat "$SCRIPT_DIR/.image-tag")"
fi

SERVICES=("$@")
if [ ${#SERVICES[@]} -eq 0 ]; then
    SERVICES=(users pharmacy gateway ui)
fi

echo "=== Desplegando versión $TAG ==="

for service in "${SERVICES[@]}"; do
    # servicio -> Deployment (el contenedor y la imagen tienen el mismo nombre)
    case "$service" in
        users)    deployment=pharmago-users-service ;;
        pharmacy) deployment=pharmago-pharmacy-service ;;
        gateway)  deployment=pharmago-api-gateway ;;
        ui)       deployment=pharmago-ui ;;
        *) echo "Error: servicio desconocido '$service'. Válidos: users, pharmacy, gateway, ui"; exit 1 ;;
    esac

    echo ""
    echo "- $deployment -> $deployment:$TAG"
    kubectl set image "deployment/$deployment" "$deployment=$deployment:$TAG" -n "$NAMESPACE"
    kubectl annotate "deployment/$deployment" "kubernetes.io/change-cause=deploy $TAG" --overwrite -n "$NAMESPACE" > /dev/null

    if ! kubectl rollout status "deployment/$deployment" -n "$NAMESPACE" --timeout="$TIMEOUT"; then
        echo "   El rollout de $deployment no terminó en $TIMEOUT. Volviendo a la versión anterior..."
        kubectl rollout undo "deployment/$deployment" -n "$NAMESPACE"
        kubectl rollout status "deployment/$deployment" -n "$NAMESPACE" --timeout="$TIMEOUT" || true
        echo "   Revisar: kubectl describe pod -n $NAMESPACE -l app=$deployment"
        exit 1
    fi
done

echo ""
echo "=== Despliegue completado (versión $TAG) ==="
kubectl get pods -n "$NAMESPACE" -o wide
