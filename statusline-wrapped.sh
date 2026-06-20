#!/bin/bash
# Chains AdSpin ad line above the HUD. Buffers stdin so both can read it.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT=$(cat)

ad_out=$(node "/Users/Jason/.adspin/statusline.mjs" 2>/dev/null)
[ -n "$ad_out" ] && printf '%s\n' "$ad_out"

echo "$INPUT" | exec "$DIR/statusline-with-usage.sh"
