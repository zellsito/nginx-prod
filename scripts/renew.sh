#!/bin/bash
set -e

if [ "$1" = "--force" ]; then
  echo "Forzando renovación de certificados..."
  docker exec certbot certbot renew --force-renewal
else
  echo "Renovando certificados (solo si están por vencer)..."
  docker exec certbot certbot renew
fi

echo "Recargando nginx..."
docker exec nginx nginx -s reload
echo "Listo."
