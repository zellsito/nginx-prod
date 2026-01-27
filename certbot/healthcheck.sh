#!/bin/sh
while IFS= read -r line; do
  [ -z "$line" ] && continue
  echo "$line" | grep -q '^#' && continue
  domain=$(echo "$line" | cut -d',' -f1 | sed 's/\*\.//')
  [ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] && exit 1
done < /etc/certbot/domains.conf
exit 0
