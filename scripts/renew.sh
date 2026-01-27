#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Reiniciando certbot (renueva certs si es necesario)..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" restart certbot

echo "Esperando a que certbot termine..."
sleep 5
docker logs certbot --tail 5

echo "Recargando nginx..."
docker exec nginx nginx -s reload
echo "Listo."
