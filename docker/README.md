# Docker Setup for Unraid/Remote Server

Run the Claude plan usage scraper on a remote server and fetch results via HTTP.

## Quick Start

### 1. Build the image

```bash
cd /path/to/claude-statusline
docker build -t claude-plan-usage -f docker/Dockerfile .
```

### 2. Initial Login (one-time setup)

Run in login mode with VNC access:

```bash
docker run -it --rm \
  -p 5900:5900 \
  -v claude-data:/data \
  claude-plan-usage login
```

Then connect via VNC (port 5900) to see the browser and log in:
- macOS: `open vnc://your-server-ip:5900`
- Or use any VNC client

After logging in, press Enter in the terminal to save the session.

### 3. Run as Daemon

```bash
docker run -d \
  --name claude-plan-usage \
  --restart unless-stopped \
  -p 8080:8080 \
  -v claude-data:/data \
  -e SCRAPE_INTERVAL=600 \
  claude-plan-usage daemon
```

Or use docker-compose:

```bash
cd docker
docker-compose up -d
```

### 4. Verify it's working

```bash
curl http://your-server-ip:8080/plan-usage.json
```

## Configure Local Mac to Fetch from Server

Set the environment variable in your shell profile (`~/.zshrc`):

```bash
export CLAUDE_PLAN_USAGE_URL="http://your-unraid-ip:8080/plan-usage.json"
```

The statusline will automatically fetch from this URL (with 60s local cache).

## Unraid-Specific Setup

### Via Docker UI

1. Go to Docker tab
2. Click "Add Container"
3. Fill in:
   - **Name**: claude-plan-usage
   - **Repository**: (build locally or use your registry)
   - **Post Arguments**: `daemon`
   - **Port Mappings**:
     - Container: 8080, Host: 8080 (HTTP)
     - Container: 5900, Host: 5900 (VNC - only needed for login)
   - **Volume Mappings**:
     - Container: /data, Host: /mnt/user/appdata/claude-plan-usage
   - **Environment Variables**:
     - SCRAPE_INTERVAL=600

### Via docker-compose on Unraid

1. Install Docker Compose Manager plugin
2. Create a stack with the `docker-compose.yml` contents

## Commands

| Command | Description |
|---------|-------------|
| `login` | Open browser for manual login (use VNC) |
| `scrape` | Run scraper once and exit |
| `serve` | Just serve JSON via HTTP |
| `daemon` | Scrape periodically + serve (default) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCRAPE_INTERVAL` | 600 | Seconds between scrapes in daemon mode |
| `HTTP_PORT` | 8080 | HTTP server port |
| `VNC_PORT` | 5900 | VNC server port |

## Endpoints

- `GET /plan-usage.json` - Current usage data
- `GET /health` - Health check

## Troubleshooting

### Check logs
```bash
docker logs claude-plan-usage
```

### Re-login if session expires
```bash
docker stop claude-plan-usage
docker run -it --rm -p 5900:5900 -v claude-data:/data claude-plan-usage login
docker start claude-plan-usage
```

### Test scrape manually
```bash
docker exec claude-plan-usage ./entrypoint.sh scrape
```
