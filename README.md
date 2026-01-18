# Claude Plan Usage Scraper

Scrapes Claude Max plan usage percentages from the web UI and serves them via HTTP for statuslines.

## Docker Setup (Unraid/Server)

### Build

```bash
cd docker
docker build -t claude-plan-usage -f Dockerfile ..
```

### First Time: Login

```bash
docker-compose run --service-ports login
```

1. Open VNC at `http://your-server:5901/vnc.html` (password: `claude`)
2. Log into claude.ai in the browser
3. Press **Enter** in terminal when done

### Run Daemon

```bash
docker-compose up -d scraper
```

Scrapes every 10 minutes and serves JSON at:
```
http://your-server:8577/plan-usage.json
```

### Re-login (when session expires)

```bash
docker-compose down
docker-compose run --service-ports login
# Connect to VNC, log in, press Enter
docker-compose up -d scraper
```

## Output Format

```json
{
  "five_hour_percent": 18,
  "weekly_percent": 33,
  "resets_in": "3h 32m",
  "resets_in_minutes": 212,
  "fetched_at": "2026-01-18T21:40:00.000Z"
}
```

## Statusline Integration

Set the environment variable in your Claude Code config:
```bash
export CLAUDE_PLAN_USAGE_URL="http://192.168.2.222:8577/plan-usage.json"
```

The statusline.sh will fetch from this URL instead of a local file.
