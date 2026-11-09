#!/bin/sh
# Chaos: muchas requests a login. Uso: ./load-requests.sh [cantidad] [url]
# Requiere port-forward activo (kubectl port-forward svc/pharmago-api-gateway 5000:80 -n pharmago).
URL="${2:-http://127.0.0.1:5000/api/login}"
N="${1:-500}"
BODY='{"userName":"x","password":"y"}'

# Sin port-forward todos los curl fallan sin avisar: verificar antes que el gateway responda
if ! curl -s -o /dev/null -m 5 -X POST "$URL" -H "Content-Type: application/json" -d "$BODY"; then
  echo "Error: no se pudo conectar a $URL"
  echo "  ¿Está activo el port-forward? kubectl port-forward svc/pharmago-api-gateway 5000:80 -n pharmago"
  exit 1
fi

echo "Load: $N requests a $URL"
# Los códigos van por un pipe y no a un archivo: escribir en paralelo al mismo archivo pierde líneas en Windows
# 429 = cortadas por el rate limit del gateway, 000 = sin respuesta
echo "Respuestas por código:"
(
  i=0
  while [ $i -lt $N ]; do
    curl -s -o /dev/null -m 30 -w "%{http_code}\n" -X POST "$URL" -H "Content-Type: application/json" -d "$BODY" &
    i=$((i+1))
  done
  wait
) | sort | uniq -c
echo "Done"
