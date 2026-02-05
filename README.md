# SmokePing Docker

[![Docker Pulls](https://img.shields.io/docker/pulls/sistemasminorisa/smokeping.svg)](https://hub.docker.com/r/sistemasminorisa/smokeping)

A production-ready SmokePing Docker image with a modern frontend, integrated traceroute history, and Telegram alerts. Built by network engineers, for network engineers.

Based on [linuxserver/smokeping](https://hub.docker.com/r/linuxserver/smokeping).

---

## What's different about this image?

We run this in production at [everyWAN](https://everywan.com) to monitor our network across multiple locations. After months of tweaking configs and writing custom scripts, we decided to package everything into a single image that just works.

**What you get:**

- Modern, responsive web interface (not the default 2005-era look)
- Traceroute panel with full history for every target (3h, 10d, 360 days)
- Telegram alerts for packet loss, latency spikes, and route changes
- Multi-location monitoring with Master/Slave architecture
- Full branding customization via environment variables

The frontend and all scripts live inside the image. You just mount your config and data volumes.

---

## Quick Start

```bash
docker run -d \
  --name smokeping \
  -p 80:80 \
  --cap-add NET_RAW \
  --cap-add NET_ADMIN \
  -v ./config:/config \
  -v ./data:/data \
  sistemasminorisa/smokeping:latest
```

Or with docker-compose:

```yaml
version: '3.8'
services:
  smokeping:
    image: sistemasminorisa/smokeping:latest
    ports:
      - "80:80"
    cap_add:
      - NET_RAW
      - NET_ADMIN
    volumes:
      - ./config:/config
      - ./data:/data
    environment:
      - TZ=Europe/Madrid
      - TELEGRAM_BOT_TOKEN=your_token
      - TELEGRAM_CHAT_ID=your_chat_id
```

That's it. Open `http://localhost` and you're monitoring.

---

## Deployment Options

We've included several compose files depending on your setup:

| File | Use Case |
|------|----------|
| `docker-compose.yml` | Standalone, single server |
| `docker-compose.swarm.yml` | Docker Swarm, port 80 exposed |
| `docker-compose.traefik.yml` | Behind existing Traefik proxy |
| `docker-compose.full-stack.yml` | Includes Traefik v3 |
| `docker-compose.slave.yml` | Slave instance for multi-location |

---

## Adding Your Own Targets

Create a `config/Targets` file:

```ini
*** Targets ***

+Production
menu = Production
title = Production Servers

++WebServer
menu = Web Server
title = Main Web Server
host = web.example.com
alerts = bigloss,someloss

++Database
menu = Database
title = PostgreSQL Primary
host = db.example.com
traceroute_mode = tcp
```

The image comes with example targets (CDNs, DNS providers, etc.) to get you started. Replace them with your infrastructure.

---

## Telegram Alerts

The alert system monitors three things:

1. **Packet Loss** — Configurable thresholds (some loss, total loss)
2. **Latency Spikes** — Sudden increases in RTT
3. **Route Changes** — When your upstream provider changes

Route change detection is smart: it ignores internal load balancing and only alerts when the actual provider changes (e.g., Telia → Cogent).

### Configuration

```yaml
environment:
  - TELEGRAM_BOT_TOKEN=123456789:AbCdEfGhIjKlMnOpQrStUvWxYz
  - TELEGRAM_CHAT_ID=-100123456789
```

Alerts are defined in `config/Alerts`. Assign them to targets with:

```ini
++MyServer
host = 1.2.3.4
alerts = bigloss,someloss,rttdetect
```

---

## Traceroute History

Every target gets a traceroute panel showing:

- Current route (live)
- Historical routes with timestamps
- Filterable by date and hour

The daemon runs every 5 minutes by default and keeps 365 days of history.

### Per-target mode

```ini
++FirewalledServer
host = 5.6.7.8
traceroute_mode = tcp    # Options: icmp (default), udp, tcp
```

---

## Multi-Location Monitoring

Deploy multiple instances to monitor from different geographic locations.

```
    MASTER (HQ)
        ▲
        │ HTTP
    ┌───┴───┐
    │       │
 SLAVE   SLAVE
 (NYC)  (Tokyo)
```

Each instance runs its own traceroute daemon with local history. The master aggregates all latency data.

### Slave Configuration

```yaml
environment:
  - MASTER_URL=https://master.example.com/smokeping/smokeping.cgi
  - SHARED_SECRET=your_secret_key
  - CACHE_DIR=/var/lib/smokeping
```

On the master, register slaves in `config/Slaves`:

```ini
*** Slaves ***
secrets=/config/smokeping_secrets

+nyc-slave
display_name = New York
color = 00ff00
```

See `docker-compose.slave.yml` for a complete example.

---

## Customization

Everything is configurable via environment variables:

| Variable | Description |
|----------|-------------|
| `SMOKEPING_LOGO_URL` | Your logo (URL or path) |
| `SMOKEPING_BRAND_NAME` | Company name in footer |
| `SMOKEPING_BRAND_URL` | Link to your website |
| `SMOKEPING_COLOR_SIDEBAR_BG` | Sidebar color (hex) |
| `SMOKEPING_TITLE` | Page title |
| `SMOKEPING_OWNER` | Owner name |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token |
| `TELEGRAM_CHAT_ID` | Telegram chat/channel ID |
| `TRACEPING_INTERVAL` | Traceroute interval (seconds) |
| `TRACEPING_RETENTION_DAYS` | History retention (days) |
| `TZ` | Timezone |
| `PUID` / `PGID` | User/Group ID |

---

## Troubleshooting

**"No such file or directory" for .rrd files**

Normal on first run. RRD files are generated after the first probe cycle (~5 minutes).

**Logo not showing**

Check that `SMOKEPING_LOGO_URL` points to an accessible image. For local files, mount them in the container.

**Traceroute shows nothing**

The daemon needs NET_RAW and NET_ADMIN capabilities. Check your compose file.

---

## Links

- [Docker Hub](https://hub.docker.com/r/sistemasminorisa/smokeping)
- [SmokePing Documentation](https://oss.oetiker.ch/smokeping/)
- [LinuxServer.io Base Image](https://www.linuxserver.io/)

---

Built and maintained by [everyWAN](https://everywan.com)
