#!/bin/bash
set -e
echo "Forzando renovación de certificados..."
docker exec certbot certbot renew --force-renewal
echo "Recargando nginx..."
docker exec nginx nginx -s reload
echo "Listo."
