# Claude Plan Usage Fetcher

Fetches Claude plan usage percentages from the Anthropic OAuth API and serves them for statuslines.

**Much simpler than web scraping!** No browser, no sessions, just a direct API call using your existing Claude Code credentials.

## Prerequisites

You must have Claude Code CLI authenticated:
```bash
claude auth login
```

This creates `~/.cli-proxy-api/claude-{email}.json` which contains the OAuth token.

## Quick Start

### One-time fetch
```bash
cd ~/Development/claude-statusline
npm run dev
```

Output written to: `~/.claude/plan-usage.json`

### Run as daemon (refreshes every 10 minutes)
```bash
npm run dev -- --daemon
```

### Custom refresh interval (5 minutes)
```bash
npm run dev -- --daemon --interval 300
```

## Auto-Start on Login (macOS) ✅

The service is configured to run automatically on startup via LaunchAgent.

### Setup (Already Done!)

The LaunchAgent is installed at:
- `~/Library/LaunchAgents/com.claude.plan-usage.plist`

It will:
- ✅ Start automatically on login
- ✅ Restart automatically if it crashes
- ✅ Refresh usage data every 5 minutes
- ✅ Survive computer restarts

### Management Commands

```bash
cd ~/Development/claude-statusline

# Check status
./manage.sh status

# Start/stop/restart
./manage.sh start
./manage.sh stop
./manage.sh restart

# View logs
./manage.sh logs      # Last 20 lines
./manage.sh tail      # Follow in real-time

# View current data
./manage.sh data
```

### File Locations

- **Output Data:** `~/.claude/plan-usage.json` (updated every 5 min)
- **Logs:** `~/.claude/plan-usage.log`
- **Error Logs:** `~/.claude/plan-usage.error.log`

### Verify It Survives Reboot

1. Restart your Mac
2. After login, run: `./manage.sh status`
3. Should show "✓ Service is running"

## Output Format

```json
{
  "five_hour_percent": 92,
  "weekly_percent": 99,
  "sonnet_percent": 90,
  "opus_percent": null,
  "extra_percent": -4,
  "resets_in": "4h 21m",
  "resets_in_minutes": 265,
  "fetched_at": "2026-01-29T14:38:11.920Z",
  "email": "you@gmail.com"
}
```

## Statusline Integration

Your Claude Code statusline script can read from `~/.claude/plan-usage.json`:

```bash
#!/bin/bash
USAGE_FILE="$HOME/.claude/plan-usage.json"

if [ -f "$USAGE_FILE" ]; then
    five_hour=$(jq -r '.five_hour_percent // "?"' "$USAGE_FILE")
    weekly=$(jq -r '.weekly_percent // "?"' "$USAGE_FILE")
    resets=$(jq -r '.resets_in // "?"' "$USAGE_FILE")
    echo "5h:${five_hour}% wk:${weekly}% (${resets})"
else
    echo "No usage data"
fi
```

**Simple one-liner:**
```bash
jq -r '"5h:\(.five_hour_percent)% wk:\(.weekly_percent)%"' ~/.claude/plan-usage.json
```

## Building

```bash
npm run build
```

Compiled output in `dist/` directory.

## How It Works

1. Reads OAuth token from `~/.cli-proxy-api/claude-{email}.json`
2. Calls `https://api.anthropic.com/api/oauth/usage`
3. Calculates remaining percentages (100 - utilization)
4. Writes to `~/.claude/plan-usage.json`

No browser automation, no cookies, no sessions to manage!

## Troubleshooting

### Service not running after reboot

```bash
# Check if LaunchAgent loaded
launchctl list | grep claude

# Manually load
launchctl load ~/Library/LaunchAgents/com.claude.plan-usage.plist

# Check logs
./manage.sh logs
```

### "No Claude auth files found"

You need to authenticate with Claude Code CLI first:
```bash
claude auth login
```

### Token expired

Claude Code OAuth tokens expire after ~1 hour. Re-authenticate:
```bash
claude auth login
./manage.sh restart
```

## Migration from v1 (Playwright)

**v2 is MUCH simpler:**

| Feature | v1 (Playwright) | v2 (OAuth API) |
|---------|----------------|----------------|
| Dependencies | Playwright + browser | None (just Node.js) |
| Setup | VNC, Docker, manual login | Just `claude auth login` |
| Startup time | ~30 seconds | Instant |
| Maintenance | Session expires, UI breaks | Token auto-refreshed |
| Cloudflare | ❌ Blocked | ✅ Works |

**To migrate:**
1. ✅ Already done - new code is in place
2. ✅ LaunchAgent configured
3. ✅ Service running automatically

## Benefits

- ✅ No Playwright dependency (saved 3 packages)
- ✅ No browser automation needed
- ✅ No login sessions to maintain
- ✅ Instant startup (was ~30s before)
- ✅ Works with Cloudflare (direct API)
- ✅ Survives reboots automatically
- ✅ Simpler codebase (348 lines vs 650+)

## License

MIT
