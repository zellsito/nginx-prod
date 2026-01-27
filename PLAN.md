# SSL Wildcard con DNS-01 + Cloudflare

## Objetivo

Certificado wildcard vía Let's Encrypt usando el challenge DNS-01 con Cloudflare como proveedor DNS.

- Un certificado por grupo de dominios definido en `domains.conf`.
- Renovación automática cada 12 horas con reload de nginx.
- Todo corre en Docker (nginx + certbot).

---

## Arquitectura

```
                ┌────────────┐
 Internet ──────┤  nginx:443 ├──── proxy_pass ──── backends (Docker)
                │  nginx:80  │
                └─────┬──────┘
                      │ depends_on (healthy)
                ┌─────┴──────┐
                │  certbot   │──── DNS-01 challenge ──── Cloudflare API
                └────────────┘
                      │
              /etc/letsencrypt (volumen compartido)
```

- **certbot** arranca primero, genera los certificados y queda en loop renovando cada 12h.
- **nginx** espera a que certbot pase el healthcheck (certs existentes) antes de iniciar.
- nginx hace reload automático cada 6h para tomar certificados renovados.

---

## Estructura de archivos

```
nginx-prod/
├── docker-compose.yml          # Orquestación nginx + certbot
├── PLAN.md                     # Este documento
│
├── certbot/
│   ├── cf.ini                  # API token de Cloudflare (chmod 600)
│   ├── domains.conf            # Dominios a certificar (1 línea = 1 cert)
│   ├── renew-loop.sh           # Entrypoint del contenedor certbot
│   └── healthcheck.sh          # Healthcheck: verifica que los certs existan
│
├── templates/
│   └── site.conf.template      # Template nginx para nuevos sitios
│
├── letsencrypt/                # Certs generados por certbot (bind mount)
│
├── nginx/
│   ├── ssl.conf                # Parámetros SSL compartidos
│   └── conf.d/
│       ├── default.conf        # Catch-all puerto 80
│       └── <domain>.conf       # Generados por add-domain.sh
│
└── scripts/
    ├── start.sh                # docker compose up -d
    ├── stop.sh                 # docker compose down
    ├── reload.sh               # Reload nginx
    ├── renew.sh                # Forzar renovación manual + reload
    ├── add-domain.sh           # Agregar dominio nuevo (todo-en-uno)
    ├── logs.sh                 # Ver logs de containers
    └── status.sh               # Ver estado de containers
```

---

## Detalle de cada archivo

### `certbot/cf.ini`

Credencial de Cloudflare para el challenge DNS-01. Debe tener permisos `600`.

```ini
dns_cloudflare_api_token = <CLOUDFLARE_API_TOKEN>
```

El token necesita el permiso `Zone:DNS:Edit` en Cloudflare.

---

### `certbot/domains.conf`

Cada línea define un certificado. Los dominios separados por coma se incluyen como SANs en el mismo cert. Líneas vacías y comentarios (`#`) se ignoran.

```
*.example.com,example.com
```

El nombre del certificado (directorio en `/etc/letsencrypt/live/`) se deriva del primer dominio quitando `*.` — en este caso: `example.com`.

---

### `certbot/renew-loop.sh`

Entrypoint del contenedor certbot. Dos fases:

1. **Emisión inicial**: recorre `domains.conf` y ejecuta `certbot certonly` con `--keep-until-expiring` para cada línea (no regenera si ya existe y es válido).
2. **Loop de renovación**: `sleep 12h` seguido de `certbot renew`.

```
┌─ Lee domains.conf ─┐
│  Para cada línea:   │
│  certbot certonly   │
│  --dns-cloudflare   │
│  --keep-existing    │
└─────────┬───────────┘
          │
    ┌─────▼─────┐
    │ sleep 12h │◄──┐
    │   renew   │───┘
    └───────────┘
```

---

### `certbot/healthcheck.sh`

Verifica que cada dominio en `domains.conf` tenga su certificado generado. Docker usa esto para `service_healthy`.

Retries configurados: 30 intentos cada 10s = 5 minutos máximo de espera para que certbot genere los certs antes de que nginx arranque.

---

### `docker-compose.yml`

Dos servicios en la red externa `web_net`:

| Servicio | Imagen | Función |
|---|---|---|
| `nginx` | `nginx:latest` | Reverse proxy con SSL termination |
| `certbot` | `certbot/dns-cloudflare` | Emisión y renovación de certs |

Puntos clave:
- **nginx** expone puertos `80` y `443`.
- **nginx** tiene un `command` custom que hace `nginx -s reload` cada 6h para tomar certs renovados.
- **nginx** depende de `certbot` con `condition: service_healthy`.
- **certbot** monta `cf.ini`, `domains.conf`, los scripts, y el volumen `letsencrypt`.
- El volumen `./letsencrypt` es compartido entre ambos (certbot escribe, nginx lee en `:ro`).

---

### `nginx/ssl.conf`

Parámetros SSL compartidos, incluidos vía `include /etc/nginx/ssl.conf;` desde cada server block HTTPS. **No** contiene rutas a certificados (cada sitio define las suyas).

Contenido:
- `ssl_protocols TLSv1.2 TLSv1.3`
- Ciphers modernos (ECDHE + AES-GCM/CHACHA20)
- `ssl_session_cache shared:SSL:10m`
- `ssl_session_timeout 1d`
- `ssl_session_tickets off`
- Header HSTS (`Strict-Transport-Security: max-age=63072000`)

---

### `nginx/conf.d/default.conf`

Catch-all solo en puerto 80. Responde "It works!" para requests sin server_name matcheado.

No hay bloque 443 en default — cada sitio maneja su propio server block HTTPS con sus certificados.

---

### `nginx/conf.d/<domain>.conf`

Generados por `add-domain.sh` desde el template. Dos server blocks:

| Puerto | Función |
|---|---|
| 80 | Redirect 301 a HTTPS |
| 443 | SSL termination + proxy al backend |

El bloque 443 usa el certificado wildcard correspondiente al root domain.

---

### `templates/site.conf.template`

Template para generar configs nginx de nuevos sitios. Tiene tres placeholders:

| Placeholder | Descripción | Ejemplo |
|---|---|---|
| `{{DOMAIN}}` | FQDN del sitio | `app.example.com` |
| `{{CERT_NAME}}` | Nombre del cert (directorio en letsencrypt/live/) | `example.com` |
| `{{BACKEND}}` | Host:puerto del backend | `my-backend:3000` |

`add-domain.sh` hace el reemplazo con `sed`.

---

### Scripts

Todos corren desde el **host**. Ubicados en `scripts/`.

#### `scripts/start.sh`
```bash
docker compose up -d
```

#### `scripts/stop.sh`
```bash
docker compose down
```

#### `scripts/reload.sh`
```bash
docker exec nginx nginx -s reload
```

#### `scripts/renew.sh`
Fuerza renovación inmediata de todos los certs y recarga nginx:
```bash
docker exec certbot certbot renew --force-renewal
docker exec nginx nginx -s reload
```

#### `scripts/logs.sh [servicio]`
```bash
docker compose logs -f "$@"
```
Sin argumentos muestra todos. Con argumento (`nginx`, `certbot`) filtra.

#### `scripts/status.sh`
```bash
docker compose ps
```

#### `scripts/add-domain.sh <dominio> <backend>`
Script todo-en-uno para agregar un nuevo dominio. Pasos:

1. Determina el `CERT_NAME` (dominio raíz del FQDN).
2. Si el wildcard ya cubre el dominio, no modifica `domains.conf`.
3. Genera `nginx/conf.d/<dominio>.conf` desde el template.
4. Reinicia certbot para que genere el cert si es necesario.
5. Espera a que el certificado exista en disco.
6. Recarga nginx.

---

## Flujo de operación

### Primer deploy

```bash
# 1. Configurar token de Cloudflare
vim certbot/cf.ini

# 2. Levantar todo
./scripts/start.sh

# 3. certbot genera certs (DNS-01 challenge)
# 4. healthcheck pasa → nginx arranca
# 5. Listo
```

### Agregar un dominio nuevo

```bash
./scripts/add-domain.sh app.example.com my-backend:3000
```

El script hace todo automáticamente: config nginx, cert (si es necesario), reload.

### Forzar renovación manual

```bash
./scripts/renew.sh
```

### Renovación automática

No requiere intervención. certbot renueva cada 12h, nginx recarga cada 6h.

---

## Verificación

| Test | Comando | Resultado esperado |
|---|---|---|
| HTTP redirect | `curl -I http://app.example.com` | `301` → `https://...` |
| HTTPS proxy | `curl -I https://app.example.com` | `200` del backend |
| Cert válido | `openssl s_client -connect app.example.com:443` | Cert wildcard válido |
| Containers OK | `./scripts/status.sh` | nginx y certbot running/healthy |

---

## Notas de seguridad

- `certbot/cf.ini` contiene el API token de Cloudflare. **No commitear** — agregar a `.gitignore`.
- El volumen `letsencrypt/` contiene claves privadas. **No commitear** — agregar a `.gitignore`.
- `cf.ini` debe tener permisos `600` dentro del contenedor (montado como `:ro`).
- El token de Cloudflare solo necesita el permiso `Zone:DNS:Edit` (mínimo privilegio).
