# Local Media Server

This repository contains a simple template for a personal media server with streaming support.

## Setup and Run

- Initialize applications with `docker compose up -d`;
- Configure system-wide mounts for `media` and `torrent` directories;
    - `config`, `cache` and `theme` directories are automatically managed by each application;
- Allow network traffic for each application;
    - Jellyfin: `8096/HTTP`, `8920/HTTPS`
    - Radarr: `7878/HTTP`
    - Sonarr: `8989/HTTP`
    - Prowlar: `9696/HTTP`
    - qBittorrent: `3344/HTTP`
    - Bazarr: `6767/HTTP`
- Access each application web-interfaces and configure them accordingly;

## Detailed Setup Guide

### Overview
This repository contains a Docker Compose configuration for setting up a Jellyfin media server with torrent integration.

### Included Services

- **Caddy** - Reverse proxy and automatic HTTPS via Let's Encrypt
- **Jellyfin** - Media server application
- **qBittorrent** - Torrent client for downloading content
- **Prowlarr** - Indexer search aggregator
- **Radarr** - Movie management
- **Sonarr** - TV show management
- **Bazarr** - Subtitle management
- **cloudflare-ddns** - Keeps a Cloudflare DNS record pointed at this host's current public IP

### Attaching Services from Other Repositories

All services run on a shared Docker network named `homelab`, created by this stack.
To plug a container from another repository into it, declare the network as external
in that repository's `docker-compose.yaml`:

```yaml
services:
  my-service:
    image: my/image
    networks:
      - homelab

networks:
  homelab:
    external: true
```

Start this stack first so the network exists, then bring the other stack up as usual.
Containers reach each other by service/container name (e.g. `http://jellyfin:8096`),
so a plugged-in service can be reverse-proxied by adding a block to the `Caddyfile`:

```
my-service.example.com {
    reverse_proxy my-service:8080
}
```

### Environment Variables

Configure the following variables in your `.env` file:

| Variable | Description | Default |
|----------|-------------|---------|
| `JELLYFIN_DOMAIN` | Domain name for automatic HTTPS | — |
| `ACME_EMAIL` | Email for Let's Encrypt notifications | — |
| `MEDIA_PATH` | Path to Jellyfin media collection | — |
| `MEDIA_2_PATH` | Path to secondary media collection | — |
| `TORRENTS_PATH` | Path for downloaded torrents | — |
| `PUID` | User ID for containers | 1001 |
| `PGID` | Group ID for containers | 1001 |
| `TZ` | Timezone | America/Fortaleza |
| `LAN_IP` | Host IP that published ports bind to (required, keeps LAN services off `0.0.0.0`) | — |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token with `Zone:DNS:Edit` on the target zone | — |
| `CLOUDFLARE_ZONE_ID` | Zone ID that owns the record(s) to update | — |
| `CLOUDFLARE_RECORD_NAME` | Comma-separated record name(s), e.g. `home.example.com` | — |
| `CLOUDFLARE_RECORD_TYPE` | Record type to manage (`A` or `AAAA`) | A |
| `CLOUDFLARE_TTL` | TTL applied to managed records | 300 |
| `CLOUDFLARE_PROXIED` | Whether managed records are proxied through Cloudflare | false |
| `CF_DDNS_INTERVAL_SECONDS` | Seconds between public IP checks | 300 |

### Quick Start

```bash
# Copy environment file template (if provided) and Caddy
cp .env.example .env
cp Caddyfile.example Caddyfile

# Edit .env with your values
nvim .env  # or use your preferred editor
nvim Caddyfile

# Start all services
docker-compose up -d

# Check status
docker-compose ps
```

### Access Services

- Jellyfin Web UI: `https://your.domain.com` (via Caddy)
- qBittorrent Web UI: `http://<LAN_IP>:3344`
- Prowlarr: `http://<LAN_IP>:9696`
- Radarr: `http://<LAN_IP>:7878`
- Sonarr: `http://<LAN_IP>:8989`
- Bazarr: `http://<LAN_IP>:6767`

`<LAN_IP>` is the value set in `.env`. These ports are bound to that IP only: `localhost`/`127.0.0.1` on the host won't reach them; use the LAN IP directly (or an SSH tunnel to it). Caddy's `80`/`443` remain on all interfaces since they serve the public domain.

### Stopping Services

```bash
docker-compose down
```

### Updating Services

```bash
docker-compose pull  # Update images
docker-compose up -d --remove-orphans
```

### Directory Structure

```
.
├── Caddyfile           # Caddy reverse proxy configuration
├── data/               # Persistent data for Caddy
├── config/             # Configuration files
│   ├── caddy/         # Caddy certificates and config
│   └── [service]/     # Each service's config folder
├── cache/              # Jellyfin cache
├── theme/              # qBittorrent themes
└── .env                # Environment variables
```

### Notes

- The `runtime: nvidia` directive on Jellyfin requires NVIDIA drivers installed on the host;
- Caddy automatically handles HTTPS with Let's Encrypt when a valid domain is configured;
- All services use the same user/group IDs (PUID/PGID) for proper file permissions;
- Torrent downloads are stored in `$TORRENTS_PATH`, which should be mapped to `/torrents` inside containers;
- `cloudflare-ddns` uses the [cloudflare-python](https://github.com/cloudflare/cloudflare-python) SDK to check the host's public IP on an interval and update the configured DNS record(s) when it changes; create a scoped API token (Zone:DNS:Edit) rather than a Global API Key;
