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
    - qBittorrent: `3344/HTTP`;
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
- qBittorrent Web UI: `http://localhost:3344`
- Prowlarr: `http://localhost:9696`
- Radarr: `http://localhost:7878`
- Sonarr: `http://localhost:8989`

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
