# Claude Plan Usage Scraper

Scrapes Claude Max plan usage percentages from the web UI and writes them to `~/.claude/plan-usage.json` for use in shell prompts or statuslines.

## Prerequisites

- macOS
- Node.js 18+ (`brew install node`)
- jq (optional, for statusline script: `brew install jq`)

## Setup

```bash
cd /Users/Jason/Development/claude-statusline
npm install
npx playwright install chromium
npm run build
```

## First Run: Log In

Open browser and log into claude.ai (session gets saved):

```bash
npm run dev -- --login
```

1. Browser opens to claude.ai
2. Log in with Google (take your time)
3. Press **Enter** in terminal when done
4. Session saved to `~/.claude/playwright-profile/`

## Usage

After logging in, scrape usage data:

```bash
npm run dev
```

Output written to `~/.claude/plan-usage.json`:
```json
{
  "five_hour_percent": 34,
  "weekly_percent": 62,
  "resets_in": "2h 40m",
  "resets_in_minutes": 160,
  "fetched_at": "2026-01-17T15:30:00.000Z"
}
```

### Options

```bash
npm run dev -- --login    # Login mode (browser stays open until Enter)
npm run dev -- --headed   # Run with visible browser
npm run dev -- --help     # Show help
```

## Scheduled Execution (launchd)

Edit the plist template with your paths:

```bash
# Find your node path
which node

# Edit paths in the plist
nano com.username.claude-plan-usage.plist

# Copy and load
cp com.username.claude-plan-usage.plist ~/Library/LaunchAgents/com.$(whoami).claude-plan-usage.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.$(whoami).claude-plan-usage.plist

# Test it
launchctl kickstart -k gui/$(id -u)/com.$(whoami).claude-plan-usage

# Check logs
tail -f ~/Library/Logs/claude-plan-usage.log
```

## Statusline Helper

For shell prompts or tmux:

```bash
./bin/claude-plan-usage-status
# Output: C5h:34% Wk:62% ⏱2h 40m
```

### Zsh Prompt

Add to `~/.zshrc`:
```bash
RPROMPT='$(/Users/Jason/Development/claude-statusline/bin/claude-plan-usage-status 2>/dev/null)'
```

### tmux

Add to `~/.tmux.conf`:
```bash
set -g status-right '#(/Users/Jason/Development/claude-statusline/bin/claude-plan-usage-status) | %H:%M'
```

## Re-login

If session expires, run `--login` again:

```bash
npm run dev -- --login
```

## Files

- `~/.claude/playwright-profile/` - Saved browser session
- `~/.claude/plan-usage.json` - Usage data output
