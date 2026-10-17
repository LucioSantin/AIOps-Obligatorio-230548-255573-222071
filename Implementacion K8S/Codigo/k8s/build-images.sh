#!/bin/bash
# Script para construir y cargar imágenes Docker en Minikube (multi-nodo)
# Funciona en Linux y Mac
# Uso:
#   ./build-images.sh                       # construye todas las imágenes
#   ./build-images.sh gateway users         # solo algunas (users, pharmacy, gateway, ui)
#   TAG=v2 ./build-images.sh                # tag explícito
#
# Cada imagen se etiqueta con una versión única (hash corto del commit, con
# sufijo -dirty-<timestamp> si hay cambios sin commitear en Backend/Frontend)
# y además con :latest (usado por los manifiestos en la instalación inicial).
# El tag generado se guarda en .image-tag para que deploy.sh lo use.

set -e

echo "=== Construyendo y cargando imágenes Docker en Minikube ==="

# Verificar que docker está disponible
if ! command -v docker &> /dev/null; then
    echo "Error: Docker no está instalado o no está en el PATH"
    exit 1
fi

# Verificar que minikube está corriendo
if ! minikube status &> /dev/null; then
    echo "Error: Minikube no está corriendo. Ejecuta: minikube start --nodes 3"
    exit 1
fi

# Obtener el directorio base (donde está este script)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CODE_DIR="$(dirname "$SCRIPT_DIR")"

SERVICES=("$@")
if [ ${#SERVICES[@]} -eq 0 ]; then
    SERVICES=(users pharmacy gateway ui)
fi

# Calcular el tag de la versión
if [ -z "$TAG" ]; then
    TAG="$(git -C "$CODE_DIR" rev-parse --short HEAD)"
    if [ -n "$(git -C "$CODE_DIR" status --porcelain -- Backend Frontend)" ]; then
        TAG="$TAG-dirty-$(date +%Y%m%d%H%M%S)"
    fi
fi
echo "Tag de versión: $TAG"

for service in "${SERVICES[@]}"; do
    # servicio -> imagen, directorio de contexto y Dockerfile
    case "$service" in
        users)    image=pharmago-users-service;    context=Backend;  dockerfile=PharmaGo.UsersService/Dockerfile ;;
        pharmacy) image=pharmago-pharmacy-service; context=Backend;  dockerfile=PharmaGo.PharmacyService/Dockerfile ;;
        gateway)  image=pharmago-api-gateway;      context=Backend;  dockerfile=PharmaGo.ApiGateway/Dockerfile ;;
        ui)       image=pharmago-ui;               context=Frontend; dockerfile=Dockerfile ;;
        *) echo "Error: servicio desconocido '$service'. Válidos: users, pharmacy, gateway, ui"; exit 1 ;;
    esac

    echo ""
    echo "  - $image:$TAG..."
    cd "$CODE_DIR/$context"
    docker build -f "$dockerfile" -t "$image:$TAG" -t "$image:latest" .
    minikube image load "$image:$TAG"
    minikube image load "$image:latest"
done

cd "$SCRIPT_DIR"
printf '%s' "$TAG" > "$SCRIPT_DIR/.image-tag"

echo ""
echo "=== Imágenes construidas y cargadas exitosamente (tag: $TAG) ==="
echo "Para desplegarlas sin downtime: ./deploy.sh ${SERVICES[*]}"
echo ""
echo "Verificando imágenes en Minikube..."
minikube image ls | grep pharmago
