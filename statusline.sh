#!/bin/bash
# Claude Code StatusLine - Box Layout with Git, Path & Usage
# Top box: MODEL, VERSION, CONTEXT, PROJECT, ELAPSED, BRANCH, THINKING, PATH bar
# Bottom box: IN, OUT, CACHE, SESSION cost, BLOCK/WEEK bars, RESETS, EXTRA

input=$(cat)
if [ -z "$input" ]; then printf "Claude"; exit 0; fi

# ── Colors (original oh-my-posh theme) ─────────────────────
e=$'\033'
blue="${e}[38;2;80;180;255m"
orange="${e}[38;2;255;200;100m"
green="${e}[38;2;50;230;50m"
cyan="${e}[38;2;80;230;230m"
red="${e}[38;2;255;100;100m"
yellow="${e}[38;2;240;220;50m"
white="${e}[38;2;240;240;240m"
dm="${e}[2m"
rs="${e}[0m"

W=96  # inner content width

# ── Box Drawing ─────────────────────────────────────────────
box_line() { printf "${dm}%s" "$1"; for ((i=0;i<W+2;i++)); do printf "─"; done; printf "%s${rs}" "$2"; }

# ── Line Builder ────────────────────────────────────────────
_s="" _v=0
_begin()   { _s=""; _v=0; }
_label()   { _s+="${white}$1${rs}"; _v=$((_v+${#1})); }
_val()     { local c="${2:-$green}"; _s+="${c}$1${rs}"; _v=$((_v+${#1})); }
_gap()     { _s+=$(printf "%*s" "$1" ""); _v=$((_v+$1)); }
_pad_to()  { local p=$(($1-_v)); [ "$p" -gt 0 ] && { _s+=$(printf "%*s" "$p" ""); _v=$1; }; }
_bar()     { _s+="$1"; _v=$((_v+$2)); }
_emit()    { local p=$((W-_v)); [ "$p" -lt 0 ] && p=0; printf "${dm}│${rs} %s%*s ${dm}│${rs}" "$_s" "$p" ""; }

# ── Helpers ─────────────────────────────────────────────────
fmt() {
    local n=$1; [ "$n" = "null" ] && n=0
    if [ "$n" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(echo "scale=1; $n/1000000" | bc)"
    elif [ "$n" -ge 1000 ] 2>/dev/null; then
        printf "%.1fk" "$(echo "scale=1; $n/1000" | bc)"
    else printf "%d" "$n"; fi
}

build_bar() {
    local pct=$1 width=${2:-10}
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( (pct * width + 50) / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled )) bc
    if [ "$pct" -ge 90 ]; then bc="$red"
    elif [ "$pct" -ge 70 ]; then bc="$yellow"
    elif [ "$pct" -ge 50 ]; then bc="$orange"
    else bc="$green"; fi
    local f="" emp=""
    for ((i=0;i<filled;i++)); do f+="●"; done
    for ((i=0;i<empty;i++)); do emp+="○"; done
    printf "%s%s%s%s%s" "$bc" "$f" "$dm" "$emp" "$rs"
}

time_remaining() {
    local iso="$1"
    [ -z "$iso" ] || [ "$iso" = "null" ] && return
    local ep
    ep=$(python3 -c "from datetime import datetime
s='$iso'.replace('Z','+00:00')
print(int(datetime.fromisoformat(s).timestamp()))" 2>/dev/null) || return
    [ -z "$ep" ] && return
    local d=$(( ep - $(date +%s) )); [ "$d" -lt 0 ] && d=0
    local h=$((d/3600)) m=$(((d%3600)/60))
    if [ "$h" -gt 24 ]; then printf "%dd %dh" $((h/24)) $((h%24))
    elif [ "$h" -gt 0 ]; then printf "%dh %dm" "$h" "$m"
    else printf "%dm" "$m"; fi
}

# ── Parse JSON ──────────────────────────────────────────────
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
version=$(echo "$input" | jq -r '.version // "?"')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$ctx_size" = "null" ] || [ -z "$ctx_size" ] && ctx_size=200000

in_tok=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cc_tok=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cr_tok=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
out_tok=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
[ "$in_tok" = "null" ] && in_tok=0; [ "$cc_tok" = "null" ] && cc_tok=0
[ "$cr_tok" = "null" ] && cr_tok=0; [ "$out_tok" = "null" ] && out_tok=0

total_in=$((in_tok + cc_tok + cr_tok))
total_cache=$((cc_tok + cr_tok))
[ "$ctx_size" -gt 0 ] && ctx_pct=$((total_in * 100 / ctx_size)) || ctx_pct=0
ctx_pct_str=$(printf "%.1f" "$(echo "scale=1; $total_in * 100 / $ctx_size" | bc 2>/dev/null)" 2>/dev/null || echo "0.0")

sess_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_rm=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
[ "$sess_cost" = "null" ] && sess_cost=0; [ "$dur_ms" = "null" ] && dur_ms=0
[ "$lines_add" = "null" ] && lines_add=0; [ "$lines_rm" = "null" ] && lines_rm=0

dur_s=$((dur_ms / 1000))
elapsed=$(printf "%d:%02d:%02d" $((dur_s/3600)) $(((dur_s%3600)/60)) $((dur_s%60)))

proj_dir=$(echo "$input" | jq -r '.workspace.project_dir // ""')
proj_name=$(basename "$proj_dir" 2>/dev/null)
[ -z "$proj_name" ] || [ "$proj_name" = "." ] && proj_name="~"
[ ${#proj_name} -gt 30 ] && proj_name="${proj_name:0:27}..."

# ── Git (cached) ────────────────────────────────────────────
git_cache="/tmp/claude-statusline-git-cache"
git_stale=true
if [ -f "$git_cache" ]; then
    gm=$(stat -f %m "$git_cache" 2>/dev/null || echo 0)
    [ $(($(date +%s) - gm)) -lt 5 ] && git_stale=false
fi
if $git_stale; then
    if git rev-parse --git-dir > /dev/null 2>&1; then
        gb=$(git branch --show-current 2>/dev/null)
        ut=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        st=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        md=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        gs=""
        [ "$ut" -gt 0 ] && gs+="?${ut}"
        [ "$st" -gt 0 ] && gs+="+${st}"
        [ "$md" -gt 0 ] && gs+="~${md}"
        [ -n "$gs" ] && gs=" (${gs})"
        echo "${gb}${gs}" > "$git_cache"
    else echo "" > "$git_cache"; fi
fi
git_info=$(cat "$git_cache" 2>/dev/null)

# Thinking
thinking="Off"; thinking_color="$dm"
if [ -f "$HOME/.claude/settings.json" ]; then
    tv=$(jq -r '.alwaysThinkingEnabled // false' "$HOME/.claude/settings.json" 2>/dev/null)
    [ "$tv" = "true" ] && { thinking="On"; thinking_color="$orange"; }
fi

# Formatted values
ctx_used_f=$(fmt "$total_in"); ctx_total_f=$(fmt "$ctx_size")
in_f=$(fmt "$total_in"); out_f=$(fmt "$out_tok"); cache_f=$(fmt "$total_cache")
cost_f=$(printf '$%.2f' "$sess_cost")

# ── Usage API (cached) ─────────────────────────────────────
ucache="/tmp/claude-statusline-usage-cache.json"
needs_refresh=true; udata=""
if [ -f "$ucache" ]; then
    um=$(stat -f %m "$ucache" 2>/dev/null || echo 0)
    [ $(($(date +%s) - um)) -lt 60 ] && { needs_refresh=false; udata=$(cat "$ucache" 2>/dev/null); }
fi

get_token() {
    for f in "$HOME"/.cli-proxy-api/claude-*.json; do
        [ -f "$f" ] || continue
        local t; t=$(jq -r '.access_token // empty' "$f" 2>/dev/null)
        [ -n "$t" ] && { echo "$t"; return; }
    done
    [ -f "$HOME/.claude/.credentials.json" ] && jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null
}

if $needs_refresh; then
    tok=$(get_token)
    if [ -n "$tok" ]; then
        resp=$(curl -sf --max-time 5 \
            -H "Accept: application/json" -H "Content-Type: application/json" \
            -H "Authorization: Bearer $tok" -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/${version}" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        [ -n "$resp" ] && { udata="$resp"; echo "$resp" > "$ucache"; }
    fi
    [ -z "$udata" ] && [ -f "$ucache" ] && udata=$(cat "$ucache" 2>/dev/null)
fi

block_pct=0; block_resets=""; week_pct=0; week_resets=""; extra_str=""
if [ -n "$udata" ]; then
    block_pct=$(printf "%.0f" "$(echo "$udata" | jq -r '.five_hour.utilization // 0')" 2>/dev/null || echo 0)
    block_resets=$(time_remaining "$(echo "$udata" | jq -r '.five_hour.resets_at // empty')")
    week_pct=$(printf "%.0f" "$(echo "$udata" | jq -r '.seven_day.utilization // 0')" 2>/dev/null || echo 0)
    week_resets=$(time_remaining "$(echo "$udata" | jq -r '.seven_day.resets_at // empty')")
    xen=$(echo "$udata" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
    if [ "$xen" = "true" ]; then
        xu=$(echo "$udata" | jq -r '.extra_usage.used_credits // 0' 2>/dev/null)
        xl=$(echo "$udata" | jq -r '.extra_usage.monthly_limit // 0' 2>/dev/null)
        xud=$(printf "%.2f" "$(echo "scale=2; $xu/100" | bc 2>/dev/null)")
        xld=$(printf "%.2f" "$(echo "scale=2; $xl/100" | bc 2>/dev/null)")
        extra_str="\$${xud}/\$${xld}"
    fi
fi

# ═══════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════

# ── TOP BOX ──
box_line "┌" "┐"
printf "\n"

# Row 1: MODEL | CONTEXT
_begin
_label "MODEL";   _pad_to 9; _val "$model" "$blue"
_pad_to 56
_label "CONTEXT"; _gap 2; _val "${ctx_used_f} / ${ctx_total_f}" "$orange"; _val " (${ctx_pct_str}%)" "$green"
_emit; printf "\n"

# Row 2: BRANCH | THINKING
_begin
_label "BRANCH";  _pad_to 9; _val "$git_info"
_pad_to 56
_label "THINKING"; _gap 1; _val "$thinking" "$thinking_color"
_emit; printf "\n"

# Row 3: PATH | VERSION
cur_dir=$(echo "$input" | jq -r '.workspace.current_dir // ""')
cur_dir="${cur_dir/#$HOME/~}"
max_path=$((56 - 10))
[ ${#cur_dir} -gt "$max_path" ] && cur_dir="...${cur_dir: -$((max_path - 3))}"
_begin
_label "PATH";    _pad_to 9; _val "$cur_dir"
_pad_to 56
_label "VERSION"; _gap 2; _val "$version" "$blue"
_emit; printf "\n"

box_line "└" "┘"
printf "\n"

# ── BOTTOM BOX ──
box_line "┌" "┐"
printf "\n"

# Row 1: 5HOUR bar | RESETS | SESSION
_begin
_label "5HOUR";   _pad_to 9; _bar "$(build_bar $block_pct 10)" 10; _gap 1; _val "${block_pct}%" "$cyan"
_pad_to 34
_label "RESETS";  _gap 2; _val "${block_resets:-n/a}"
_pad_to 56
_label "SESSION"; _gap 2; _val "$cost_f"
_emit; printf "\n"

# Row 2: WEEK bar | RESETS | EXTRA
_begin
_label "WEEK";    _pad_to 9; _bar "$(build_bar $week_pct 10)" 10; _gap 1; _val "${week_pct}%" "$cyan"
_pad_to 34
_label "RESETS";  _gap 2; _val "${week_resets:-n/a}"
_pad_to 56
if [ -n "$extra_str" ]; then
    _label "EXTRA"; _gap 2; _val "$extra_str" "$cyan"
else
    _label "LINES"; _gap 2; _val "+${lines_add} -${lines_rm}" "$green"
fi
_emit; printf "\n"

box_line "└" "┘"
exit 0
