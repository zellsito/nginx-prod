# nginx-prod

Nginx reverse proxy with automatic SSL wildcard certificates via Let's Encrypt DNS-01 challenge and Cloudflare.

## Features

- Wildcard SSL certificates (`*.example.com` + `example.com`)
- Automatic renewal every 12h
- Automatic nginx reload every 6h
- Add new domains with a single command
- Zero-downtime certificate rotation

## Prerequisites

- Docker and Docker Compose
- A domain managed by Cloudflare
- A Cloudflare API token with `Zone:DNS:Edit` permission
- An external Docker network called `web_net`:
  ```bash
  docker network create web_net
  ```

## Quick start

```bash
# 1. Clone
git clone https://github.com/zellsito/nginx-prod.git
cd nginx-prod

# 2. Configure Cloudflare API token
echo "dns_cloudflare_api_token = YOUR_TOKEN_HERE" > certbot/cf.ini
chmod 600 certbot/cf.ini

# 3. Start
./scripts/start.sh

# 4. Add your first domain
./scripts/add-domain.sh app.example.com my-backend:80
```

## Adding a domain

```bash
./scripts/add-domain.sh <domain> <backend>
```

Example:
```bash
./scripts/add-domain.sh app.example.com my-backend:80
./scripts/add-domain.sh api.example.com api-service:3000
```

The script automatically:
1. Adds the wildcard entry to `certbot/domains.conf` (if not already present)
2. Generates an nginx config from the template
3. Restarts certbot to issue the certificate
4. Waits for the certificate to be ready
5. Reloads nginx

## Scripts

| Script | Description |
|---|---|
| `scripts/start.sh` | Start all services |
| `scripts/stop.sh` | Stop all services |
| `scripts/reload.sh` | Reload nginx configuration |
| `scripts/renew.sh` | Force certificate renewal + reload |
| `scripts/add-domain.sh` | Add a new domain |
| `scripts/logs.sh` | View container logs (`logs.sh nginx`, `logs.sh certbot`, or just `logs.sh`) |
| `scripts/status.sh` | View container status |

## How it works

```
Internet ──── nginx (80/443) ──── proxy_pass ──── backend containers
                   │
                   │ depends_on (healthy)
                   │
               certbot ──── DNS-01 challenge ──── Cloudflare API
                   │
           /etc/letsencrypt (shared volume)
```

1. **certbot** starts first, reads `certbot/domains.conf`, and requests certificates via DNS-01 challenge using the Cloudflare API.
2. Docker healthcheck verifies all certificates exist before nginx starts.
3. **nginx** starts with SSL termination and proxies traffic to backend containers.
4. certbot renews certificates every 12h. nginx reloads every 6h to pick up renewed certs.

## Project structure

```
nginx-prod/
├── docker-compose.yml
├── certbot/
│   ├── cf.ini              # Cloudflare API token (not tracked by git)
│   ├── domains.conf        # Domains to certify (managed by add-domain.sh)
│   ├── renew-loop.sh       # Certbot container entrypoint
│   └── healthcheck.sh      # Verifies all certs exist
├── templates/
│   └── site.conf.template  # Nginx site template
├── letsencrypt/            # Generated certs (not tracked by git)
├── nginx/
│   ├── ssl.conf            # Shared SSL parameters
│   └── conf.d/
│       ├── default.conf    # Catch-all (port 80)
│       └── *.conf          # Generated site configs
└── scripts/
    └── ...
```

## Cloudflare API token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click **Create Token**
3. Scroll down and click **Get started** under **Custom token**
4. Configure:

| Field | Value |
|---|---|
| **Token name** | `certbot-dns` (or whatever you prefer) |
| **Permissions** | `Zone` → `DNS` → `Edit` |
| **Zone Resources** | `Include` → `All zones` |
| **Client IP Address Filtering** | `Is in` → your server's public IP |
| **TTL** | Leave empty (no expiration) |

5. Click **Continue to summary** → **Create Token**
6. Copy the token (shown only once)

To verify the token works, run this from your server:
```bash
curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer YOUR_TOKEN" -H "Content-Type: application/json"
```

Expected response: `{"result":{"status":"active"},"success":true,...}`

## License

MIT
