#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Deteniendo certbot..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" stop certbot

echo "Renovando certificados..."
docker run --rm \
  -v "$PROJECT_DIR/letsencrypt:/etc/letsencrypt" \
  -v "$PROJECT_DIR/certbot/cf.ini:/etc/cloudflare/cf.ini:ro" \
  certbot/dns-cloudflare renew

echo "Reiniciando certbot..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" start certbot

echo "Recargando nginx..."
docker exec nginx nginx -s reload
echo "Listo."
