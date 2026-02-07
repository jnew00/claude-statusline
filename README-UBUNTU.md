# Claude Plan Usage Fetcher - Ubuntu Setup

This is the Ubuntu/systemd version of the Claude plan usage fetcher. For macOS, see the main README.md.

## Prerequisites

1. **Node.js and npm** installed
2. **Claude Code CLI authenticated:**
   ```bash
   claude auth login
   ```
   This creates `~/.cli-proxy-api/claude-{email}.json` containing your OAuth token.

3. **jq** for JSON parsing (optional but recommended):
   ```bash
   sudo apt-get install jq
   ```

## Quick Start

### One-time fetch
```bash
cd ~/Development/claude-statusline
npm run dev
```

Output written to: `~/.claude/plan-usage.json`

### Run as daemon (refreshes every 10 minutes)
```bash
npm run daemon
```

### Custom refresh interval (5 minutes)
```bash
npm run dev -- --daemon --interval 300
```

## Auto-Start on Login (Ubuntu/systemd) ✅

The service is configured to run automatically via systemd user service.

### Setup (one-time)

```bash
cd ~/Development/claude-statusline
chmod +x manage-ubuntu.sh
./manage-ubuntu.sh install
./manage-ubuntu.sh start
```

It will:
- ✅ Start automatically on login
- ✅ Restart automatically if it crashes
- ✅ Refresh usage data every 10 minutes
- ✅ Survive system restarts

### Management Commands

```bash
cd ~/Development/claude-statusline

# Check status
./manage-ubuntu.sh status

# Start/stop/restart
./manage-ubuntu.sh start
./manage-ubuntu.sh stop
./manage-ubuntu.sh restart

# View logs
./manage-ubuntu.sh logs       # Last 30 lines
./manage-ubuntu.sh tail       # Follow in real-time

# View current data
./manage-ubuntu.sh data

# Uninstall service
./manage-ubuntu.sh uninstall
```

### File Locations

- **Output Data:** `~/.claude/plan-usage.json` (updated every 10 min)
- **Logs:** `~/.claude/plan-usage.log`
- **Error Logs:** `~/.claude/plan-usage.error.log`
- **Service File:** `~/.config/systemd/user/claude-plan-usage.service`
- **Wrapper Script:** `~/Development/claude-statusline/run.sh`

### Verify It Survives Reboot

1. Reboot your machine
2. After login, run: `./manage-ubuntu.sh status`
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

Your statusline script can read from `~/.claude/plan-usage.json`:

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
5. For auto-start: systemd service runs the daemon in the background

No browser automation, no cookies, no sessions to manage!

## Troubleshooting

### Service not running after reboot

```bash
# Check systemd status
systemctl --user status claude-plan-usage

# View recent logs
./manage-ubuntu.sh logs

# Restart manually
./manage-ubuntu.sh restart

# Check if systemd recognizes the service
systemctl --user list-unit-files | grep claude-plan-usage
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
./manage-ubuntu.sh restart
```

### Service fails to start

Check the service file exists:
```bash
cat ~/.config/systemd/user/claude-plan-usage.service
```

Check the run.sh script exists and is executable:
```bash
ls -la ~/Development/claude-statusline/run.sh
```

Enable logging for debugging:
```bash
journalctl --user -u claude-plan-usage -n 50
```

### npm: command not found

Make sure Node.js/npm is installed and available in your PATH.

If you used a Node version manager (nvm, n, etc.), you may need to source it in the service:
```bash
# Edit ~/.config/systemd/user/claude-plan-usage.service
# Add to [Service] section:
Environment="PATH=/home/you/.nvm/versions/node/v18.0.0/bin:/usr/local/bin:/usr/bin"
```

Then reload:
```bash
systemctl --user daemon-reload
./manage-ubuntu.sh restart
```

## Switching Between Branches

This is the **ubuntu** branch. To switch:

```bash
# For Ubuntu (this branch)
git checkout ubuntu

# For macOS
git checkout main
```

Each branch has its own service configuration and manage script.

## License

MIT
