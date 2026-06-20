# claude-statusline

Custom Claude Code statusline, with ad/monetization tools (codebacks + AdSpin
+ kickbacks webview) layered on top of it. This file documents how the pieces
fit so the setup can be repaired fast after a tool update breaks it.

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
- `statusline-wrapped.sh` — fallback pass-through that `exec`s the HUD. Not
  currently in the active chain (AdSpin owns the slot and chains via its own
  script — see render chain below). Kept for recovery.
- `statusline.sh` — older single-line version (MODEL · CONTEXT · effort). Kept
  as a fallback for the v2.1.112+ cli-truncate regression (issue #37522). Swap
  the HUD for this if the multi-line boxes truncate/jitter.
- `manage.sh` — install/symlink helper (pre-dates the ad tools).

## The render chain (important)

Claude Code allows exactly ONE `statusLine.command` in `~/.claude/settings.json`.
The working layout lets AdSpin own the slot while our HUD runs inside it:

```
~/.claude/settings.json  statusLine.command
  -> node ~/.adspin/statusline.mjs    (our chain wrapper — AdSpin ad on top)
       -> prints ad from ~/.adspin/ad.json
            -> statusline-with-usage.sh   (our HUD)
                 -> reads ~/.codebacks/state/claude-<session_id>.json  (codebacks earnings)
```

On screen: AdSpin ad line, then our HUD boxes.

**Why AdSpin owns the slot:** AdSpin re-asserts `settings.json` → its own path
every few seconds while VS Code is open. Letting it win and injecting our chain
inside `~/.adspin/statusline.mjs` is the only stable approach.

**Kickbacks CLI is off** (`~/.vibe-ads/cli.off` exists). Kickbacks earns only
via the VS Code webview surface. `~/.vibe-ads/webview.off` must NOT exist.
`spinnerVerbs` is owned by AdSpin (its spinner ad).

**AdSpin chain quirk** — AdSpin actively watches and restores both
`settings.json` AND `~/.adspin/statusline.mjs`. The chain wrapper is locked
immutable with `chflags uchg ~/.adspin/statusline.mjs` so it can't be stomped.
`~/.adspin/statusline.real.mjs` is a backup of the original bare ad script.

After an AdSpin extension update, it may fail to overwrite due to `uchg` and
fall back to showing nothing. If the statusLine goes blank: unlock, let AdSpin
re-apply its update, re-inject the chain, re-lock:
```sh
chflags nouchg ~/.adspin/statusline.mjs   # unlock so AdSpin can update
# wait ~5s for AdSpin to write its new version, then:
cp ~/.adspin/statusline.mjs ~/.adspin/statusline.real.mjs   # backup new version
# Re-inject chain (see TROUBLESHOOTING below), then:
chflags uchg ~/.adspin/statusline.mjs   # re-lock
```

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

**AdSpin / Claude Code Ads** (VS Code extension `claudecodeads.claude-code-ads`,
config in `~/.adspin/`)
- 75% dev share, PayPal weekly with $10 minimum.
- Earns via spinner (`spinnerVerbs`) and statusLine impressions (10s per
  impression). Both surfaces must be active. Requires VS Code extension running.
- Owns `settings.json` statusLine slot — re-asserts its path aggressively while
  VS Code is open. Solution: inject our HUD chain inside its own script
  (`~/.adspin/statusline.mjs`) rather than fighting for the slot.
- Ad cache: `~/.adspin/ad.json` (10 min TTL). Goes stale if VS Code is closed.
- Check earnings at claudecodeads.com or the VS Code status bar.

**kickbacks** (kickbacks.ai, VS Code extension `kickbacksai.kickbacks-ai`,
config in `~/.vibe-ads/` and `~/.kickbacks/auth.json`)
- CLI surface is OFF (`~/.vibe-ads/cli.off`). AdSpin handles CLI slots.
- Webview surface is ON (no `~/.vibe-ads/webview.off`). Earns via VS Code
  webview `view_tick` events while extension runs. 50% dev share.
- Earnings not in a local file. Check at kickbacks.ai/me or VS Code status bar.

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

**HUD disappeared after AdSpin extension update**
AdSpin overwrites `~/.adspin/statusline.mjs` on every extension update, replacing
our chain with the bare ad-only script. Re-apply the chain:
```sh
# 0. Unlock first if it's immutable:
chflags nouchg ~/.adspin/statusline.mjs
# 1. Overwrite with the chain wrapper (copies the ad logic + chains HUD):
cat > ~/.adspin/statusline.mjs << 'JSEOF'
#!/usr/bin/env node
import { readFileSync, writeSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { spawn } from "node:child_process";
const MAX_AGE_MS = 10 * 60 * 1000;
let wrote = false;
const put = (s) => { try { writeSync(1, s); wrote = true; } catch {} };
try {
  const ad = JSON.parse(readFileSync(join(homedir(), ".adspin", "ad.json"), "utf8"));
  const fresh = typeof ad.ts === "number" && Date.now() - ad.ts < MAX_AGE_MS;
  const text = typeof ad.text === "string" ? ad.text.replace(/[\x00-\x1f]/g, "") : "";
  const url = typeof ad.url === "string" &&
    /^(https|vscode|vscode-insiders|vscodium|cursor|windsurf|code-oss):\/\/|^http:\/\/(localhost|127\.0\.0\.1)([:\/]|$)/.test(ad.url)
    ? ad.url : "";
  if (fresh && text) {
    const OSC = "]8;;"; const BEL = "";
    put(url ? OSC + url + BEL + "ad · " + text + OSC + BEL : "ad · " + text);
  }
} catch {}
const HUD = "/Users/Jason/Development/claude-statusline/statusline-with-usage.sh";
const stdinMode = process.stdin.isTTY ? "ignore" : "inherit";
const child = spawn(HUD, { shell: false, stdio: [stdinMode, "pipe", "ignore"] });
let out = ""; let done = false;
const finish = () => {
  if (done) return; done = true;
  const text = out.replace(/[\r\n]+$/, "");
  if (text) put((wrote ? "\n" : "") + text);
  process.exit(0);
};
child.stdout.on("data", (d) => { out += d; });
child.stdout.on("error", () => {});
child.on("error", finish);
child.on("close", finish);
child.on("exit", () => { setTimeout(finish, 150); });
setTimeout(() => { try { child.kill(); } catch {} finish(); }, 5000);
JSEOF
# 2. Re-lock:
chflags uchg ~/.adspin/statusline.mjs
# 3. Verify:
echo '{"session_id":"x","model":{"display_name":"Sonnet 4.6"},"version":"2.1.183","workspace":{"current_dir":"'$PWD'"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":100}}}' \
  | node ~/.adspin/statusline.mjs
```

**HUD disappeared after `codebacks update` / `codebacks init`**
codebacks hard-overwrites `settings.statusLine`. AdSpin then reasserts its own
path within seconds. No manual fix needed — just wait ~5s for AdSpin to win back
the slot (which now chains the HUD). If it doesn't recover, check that
`~/.adspin/statusline.mjs` is still our chain wrapper (not the bare original).

**Check who owns the statusLine right now**
```sh
python3 -c "import json;print(json.load(open('$HOME/.claude/settings.json'))['statusLine'])"
# Should show: node "/Users/Jason/.adspin/statusline.mjs"
# Check that file is our chain wrapper (should import spawn and reference statusline-with-usage.sh):
grep -c "statusline-with-usage" ~/.adspin/statusline.mjs   # want 1
```

**Test the full chain render (no live session needed)**
```sh
rm -f /tmp/claude-statusline-usage-cache.json /tmp/claude-statusline-git-*.cache
P='{"session_id":"<a real session id from ~/.codebacks/state>","model":{"display_name":"Opus 4.8"},"version":"2.1.183","workspace":{"current_dir":"'$PWD'","project_dir":"'$PWD'"},"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":1200,"cache_creation_input_tokens":3000,"cache_read_input_tokens":45000,"output_tokens":800}},"cost":{"total_cost_usd":0.42}}'
echo "$P" | node ~/.adspin/statusline.mjs   # full chain (ad + HUD)
echo "$P" | ./statusline-with-usage.sh      # HUD only
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
