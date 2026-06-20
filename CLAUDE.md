# claude-statusline

Custom Claude Code statusline, with two third-party ad/monetization tools
(codebacks + kickbacks) layered on top of it. This file documents how the
pieces fit so the setup can be repaired fast after a tool update breaks it.

No secrets in this file (repo is public). Tokens/keys live in the keychain and
in the config files noted below, never here.

## Repo files

- `statusline-with-usage.sh` — the HUD. Two boxes. Top box is 2 lines:
  `MODEL (+effort) | CONTEXT`, then `PATH (+git branch/status) | VERSION`. The
  MODEL field appends the reasoning effort from `settings.json` `effortLevel`,
  color-ramped per tier: none=dim, low=white, medium=green, high=yellow,
  xhigh=orange, max=red. (`ultrathink` is a per-prompt thinking keyword, NOT an
  effortLevel value, so it never appears here.) The VERSION
  field shows a yellow `↑<latest>` when a newer Claude Code release exists
  (latest pulled from `https://downloads.claude.ai/claude-code-releases/latest`,
  cached 1h in `/tmp/claude-statusline-ccver-cache`, fetched in the background so
  it never blocks render; compared with `sort -V`). Bottom box: 5HOUR/WEEK usage
  + codebacks EARNED/TOTAL. This is the thing we actively maintain.
- `statusline-wrapped.sh` — thin pass-through that `exec`s the HUD. Exists as a
  stable chain target for kickbacks (see render chain below). Does not render
  anything itself anymore.
- `statusline.sh` — older single-line version (MODEL · CONTEXT · effort). Kept
  as a fallback for the v2.1.112+ cli-truncate regression (issue #37522). Swap
  the HUD for this if the multi-line boxes truncate/jitter.
- `manage.sh` — install/symlink helper (pre-dates the ad tools).

## The render chain (important)

Claude Code allows exactly ONE `statusLine.command` in `~/.claude/settings.json`.
Both ad tools want that slot. The working layout chains them:

```
~/.claude/settings.json  statusLine.command
  -> node ~/.vibe-ads/vibe-ads-statusline.mjs        (kickbacks adapter; prints ad on top)
       -> reads ~/.vibe-ads/cli-prev-statusline.json (kickbacks "PREV" chain-capture)
            -> /Users/Jason/Development/claude-statusline/statusline-wrapped.sh
                 -> exec statusline-with-usage.sh     (our HUD)
                      -> reads ~/.codebacks/state/claude-<session_id>.json  (codebacks earnings)
```

So on screen: kickbacks ad line, then our HUD boxes. Kickbacks owns the slot and
"chains" our wrapper below its ad. The wrapper path is what kickbacks captured in
its PREV file, which is why the wrapper must keep existing at that path.

## The two tools (different architectures)

**codebacks** (codebacks.com, npm `codebacks`, installed in `~/.codebacks/`)
- Earns through Claude Code HOOKS in settings.json (`codebacks-hook.js` on
  SessionStart / UserPromptSubmit / Stop / SessionEnd). The Stop hook reports the
  impression and credits cents. Earning is independent of the statusline.
- Its own statusline renderer (`~/.codebacks/bin/codebacks-statusline.js`) is
  display-only. We do NOT display it; we pull the earnings numbers straight from
  its state file into our HUD instead.
- Earnings file: `~/.codebacks/state/claude-<session_id>.json` →
  `{ cbSessionId, earnedCents, totalCents }`. earnedCents = this session,
  totalCents = lifetime. Our HUD reads these for EARNED / TOTAL.
- You do NOT need to display the codebacks ad to earn (hook-based, timestamp
  impression). Safe to hide.

**kickbacks** (kickbacks.ai, VS Code extension `kickbacksai.kickbacks-ai`,
config in `~/.vibe-ads/` and `~/.kickbacks/auth.json`)
- Earns through the VS Code extension running in the background. The extension
  (a) installs the statusLine adapter above, (b) refreshes a cached ad
  (`~/.vibe-ads/cli-ad.json`), and (c) fires `view_tick` earning events while the
  CLI is actively in use (~4s activity freshness) AND its surface is applied.
- It also patches the `claude` binary to print an ad banner. Claude Code
  auto-updates wipe that patch; the extension re-applies it within ~60s, but
  ONLY while VS Code is open with the extension active.
- CONSEQUENCE for CLI-only work: kickbacks only earns while VS Code is open in
  the background, signed in. Close VS Code and its CLI earning + ad cache go
  stale within ~90s. Unlike codebacks, you cannot fully hide it and still earn:
  the statusLine surface must stay applied and you must be actively running turns.
- Earnings are NOT written to a readable local file (only in VS Code state / its
  backend `/v1/earnings`). We deliberately do NOT pull kickbacks earnings into
  the HUD: doing so needs minting a token from a rotating refresh token, which
  races the extension's own token rotation and would log you out. Check kickbacks
  earnings at kickbacks.ai/me or in the VS Code status bar instead.

## Usage API (5HOUR / WEEK / RESETS)

The HUD calls `https://api.anthropic.com/api/oauth/usage` for the rate-limit
gauges. Token source matters:
- CORRECT: macOS keychain — `security find-generic-password -s "Claude Code-credentials" -w`
  then `.claudeAiOauth.accessToken`. This is what `get_token()` uses first.
- WRONG/dead: `~/.claude/.credentials.json` does not exist on macOS (creds are in
  the keychain). The cli-proxy token (`~/.cli-proxy-api/claude-*.json`) returns
  HTTP 429 (rate limited). If the gauges go blank again, it's almost always the
  token source — re-check keychain access.
- Response is cached 60s in `/tmp/claude-statusline-usage-cache.json`. Delete it
  to force a refresh while debugging.

## TROUBLESHOOTING / quick fixes

**HUD disappeared, only the codebacks line or only the kickbacks ad shows**
(usually right after `codebacks update` / `codebacks init` / re-enabling
kickbacks). codebacks hard-overwrites `settings.statusLine` to its own command;
kickbacks then reasserts within 60s but re-captures codebacks' line as its PREV,
bumping our wrapper out. Fix the PREV:
```sh
echo '{"statusLine":{"type":"command","command":"/Users/Jason/Development/claude-statusline/statusline-wrapped.sh","refreshInterval":1}}' \
  > ~/.vibe-ads/cli-prev-statusline.json
```
If kickbacks is NOT installed/owning the slot, point settings.json straight at
the wrapper instead:
```sh
# settings.json -> statusLine.command = /Users/Jason/Development/claude-statusline/statusline-wrapped.sh
```

**Check who owns the statusLine right now**
```sh
python3 -c "import json;print(json.load(open('$HOME/.claude/settings.json'))['statusLine'])"
cat ~/.vibe-ads/cli-prev-statusline.json   # what kickbacks chains below its ad
```

**Test the full chain render (no live session needed)**
```sh
rm -f /tmp/claude-statusline-usage-cache.json /tmp/claude-statusline-git-cache
P='{"session_id":"<a real session id from ~/.codebacks/state>","model":{"display_name":"Opus 4.8"},"version":"2.1.183","workspace":{"current_dir":"'$PWD'","project_dir":"'$PWD'"},"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":1200,"cache_creation_input_tokens":3000,"cache_read_input_tokens":45000,"output_tokens":800}},"cost":{"total_cost_usd":0.42}}'
echo "$P" | node ~/.vibe-ads/vibe-ads-statusline.mjs   # full chain (ad + HUD)
echo "$P" | ./statusline-with-usage.sh                 # HUD only
```

**EARNED / TOTAL stuck at $0.00**
- Confirm a state file exists for the live session:
  `ls ~/.codebacks/state/claude-*.json` and that it has `earnedCents`/`totalCents`.
- If a codebacks update changed the schema/path, update the jq paths in the
  "Codebacks earnings" block of `statusline-with-usage.sh`.

**5HOUR / WEEK / RESETS blank** — token source (see Usage API above). Test:
```sh
tok=$(security find-generic-password -s "Claude Code-credentials" -w | jq -r '.claudeAiOauth.accessToken')
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $tok" \
  -H "anthropic-beta: oauth-2025-04-20" https://api.anthropic.com/api/oauth/usage   # want 200
```

**EARNED/TOTAL values not aligned** — they pad to fixed column 64 via `_pad_to 64`
(labels are different lengths, so `_gap` would misalign). Keep `_pad_to`, not `_gap`.

## Updating the ad tools (what breaks, expected steps)

- Version check: `npm view codebacks version` is the installable npm version.
  codebacks' server (`https://codebacks.com/api/version`) may advertise a newer
  cli/extension that is not on npm yet, so `npx codebacks@latest update` can be a
  no-op even when it claims a newer version "exists." That is expected.
- `npx codebacks@latest update` re-wires hooks and OVERWRITES settings.statusLine
  to codebacks' bare command. After running it: redo the PREV fix above, then
  test the chain. codebacks hooks should still be 1 each (no dupes).
- kickbacks updates via the VS Code extension. After an update it says to FULLY
  quit and reopen VS Code (not just reload) to load the new build.
- Backups of settings.json are written as `~/.claude/settings.json.*backup*` /
  `.pre-codebacks-update` when we touch it. Diff against those if wiring looks off.

## Note on the bypass-permissions banner

`▶▶ bypass permissions on (shift+tab to cycle)` is a built-in Claude Code safety
indicator (shown because the `claude` alias uses `--dangerously-skip-permissions`).
It is NOT part of the statusline and there is no supported setting to hide it.
Only removable by patching the binary, which updates wipe. Leave it.
