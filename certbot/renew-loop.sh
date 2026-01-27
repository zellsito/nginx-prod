#!/bin/sh

# Emisión inicial: recorre domains.conf y genera certs
while IFS= read -r line; do
  [ -z "$line" ] && continue
  echo "$line" | grep -q '^#' && continue

  # Primer dominio como cert name (sin *.)
  cert_name=$(echo "$line" | cut -d',' -f1 | sed 's/\*\.//')

  # Armar flags -d para cada dominio en la línea
  domain_flags=""
  for domain in $(echo "$line" | tr ',' ' '); do
    domain_flags="$domain_flags -d $domain"
  done

  echo "Solicitando cert para: $line (cert-name: $cert_name)"
  certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/cloudflare/cf.ini \
    --cert-name "$cert_name" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    --keep-until-expiring \
    $domain_flags

done < /etc/certbot/domains.conf

echo "Emisión inicial completa. Entrando en loop de renovación."

# Loop: cada 12h intenta renovar
while :; do
  sleep 12h
  echo "Ejecutando renovación..."
  certbot renew
done
