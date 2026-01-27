#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOMAINS_CONF="$PROJECT_DIR/certbot/domains.conf"
TEMPLATE="$PROJECT_DIR/templates/site.conf.template"
CONF_DIR="$PROJECT_DIR/nginx/conf.d"

# --- Validar argumentos ---
if [ $# -lt 2 ]; then
  echo "Uso: $0 <dominio> <backend>"
  echo "Ejemplo: $0 app.example.com my-backend:80"
  exit 1
fi

DOMAIN="$1"
BACKEND="$2"

# --- Determinar root domain y cert name ---
DOT_COUNT=$(echo "$DOMAIN" | tr -cd '.' | wc -c)
if [ "$DOT_COUNT" -le 1 ]; then
  # Root domain (ej: example.com)
  ROOT_DOMAIN="$DOMAIN"
else
  # Subdomain (ej: app.example.com → example.com)
  ROOT_DOMAIN=$(echo "$DOMAIN" | cut -d'.' -f2-)
fi
CERT_NAME="$ROOT_DOMAIN"
WILDCARD_ENTRY="*.${ROOT_DOMAIN},${ROOT_DOMAIN}"

echo "Dominio:    $DOMAIN"
echo "Root:       $ROOT_DOMAIN"
echo "Cert name:  $CERT_NAME"
echo "Wildcard:   $WILDCARD_ENTRY"
echo ""

# --- 1. Agregar wildcard a domains.conf si no existe ---
if grep -q "^\*\.${ROOT_DOMAIN}" "$DOMAINS_CONF" 2>/dev/null; then
  echo "[domains.conf] Wildcard *.${ROOT_DOMAIN} ya existe, no se agrega."
else
  echo "$WILDCARD_ENTRY" >> "$DOMAINS_CONF"
  echo "[domains.conf] Agregado: $WILDCARD_ENTRY"
fi

# --- 2. Generar nginx conf desde template ---
CONF_FILE="$CONF_DIR/${DOMAIN}.conf"
if [ -f "$CONF_FILE" ]; then
  echo "[nginx] $CONF_FILE ya existe, se sobreescribe."
fi

sed -e "s/{{DOMAIN}}/$DOMAIN/g" \
    -e "s/{{CERT_NAME}}/$CERT_NAME/g" \
    -e "s|{{BACKEND}}|$BACKEND|g" \
    "$TEMPLATE" > "$CONF_FILE"

echo "[nginx] Creado: $CONF_FILE"

# --- 3. Restart certbot para que genere el cert ---
echo "[certbot] Reiniciando certbot..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" restart certbot

# --- 4. Esperar a que el cert exista (chequea dentro del container) ---
echo "[certbot] Esperando certificado para $CERT_NAME..."
CERT_CONTAINER_PATH="/etc/letsencrypt/live/$CERT_NAME/fullchain.pem"
TRIES=0
MAX_TRIES=60
while ! docker exec certbot test -f "$CERT_CONTAINER_PATH" 2>/dev/null; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge "$MAX_TRIES" ]; then
    echo "ERROR: Timeout esperando certificado en $CERT_CONTAINER_PATH"
    exit 1
  fi
  sleep 5
done
echo "[certbot] Certificado listo."

# --- 5. Reload nginx ---
echo "[nginx] Recargando nginx..."
docker exec nginx nginx -s reload
echo ""
echo "Listo: https://$DOMAIN"
