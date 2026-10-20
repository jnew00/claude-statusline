#!/bin/bash
# Claude Code StatusLine - Box Layout with Git & Path
# MODEL (+effort) | CONTEXT, then PATH (+git) | VERSION (+update)

input=$(cat)
if [ -z "$input" ]; then printf "Claude"; exit 0; fi

# ── Colors (original oh-my-posh theme) ─────────────────────
e=$'\033'
blue="${e}[38;2;80;180;255m"
orange="${e}[38;2;255;200;100m"
green="${e}[38;2;50;230;50m"
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

# ── Git (cached per-directory) ──────────────────────────────
# Query the session's actual dir (git -C), and key the cache by that dir so
# concurrent sessions in other repos can't leak their branch into this one.
gitdir=$(echo "$input" | jq -r '.workspace.current_dir // empty')
[ -z "$gitdir" ] && gitdir="$PWD"
dirkey=$(printf '%s' "$gitdir" | cksum | cut -d' ' -f1)
git_cache="/tmp/claude-statusline-git-${dirkey}.cache"
git_stale=true
if [ -f "$git_cache" ]; then
    gm=$(stat -f %m "$git_cache" 2>/dev/null || echo 0)
    [ $(($(date +%s) - gm)) -lt 5 ] && git_stale=false
fi
if $git_stale; then
    if git -C "$gitdir" rev-parse --git-dir > /dev/null 2>&1; then
        gb=$(git -C "$gitdir" branch --show-current 2>/dev/null)
        ut=$(git -C "$gitdir" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        st=$(git -C "$gitdir" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        md=$(git -C "$gitdir" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        gs=""
        [ "$ut" -gt 0 ] && gs+="?${ut}"
        [ "$st" -gt 0 ] && gs+="+${st}"
        [ "$md" -gt 0 ] && gs+="~${md}"
        [ -n "$gs" ] && gs=" (${gs})"
        echo "${gb}${gs}" > "$git_cache"
    else echo "" > "$git_cache"; fi
fi
git_info=$(cat "$git_cache" 2>/dev/null)

# ── Claude Code update check (cached 1h, refreshed in background) ──
ccver_cache="/tmp/claude-statusline-ccver-cache"
ccver_stale=true
if [ -f "$ccver_cache" ]; then
    ccm=$(stat -f %m "$ccver_cache" 2>/dev/null || echo 0)
    [ $(($(date +%s) - ccm)) -lt 3600 ] && ccver_stale=false
fi
if $ccver_stale; then
    touch "$ccver_cache" 2>/dev/null   # throttle: claim freshness before fetching
    { curl -sf --max-time 4 "https://downloads.claude.ai/claude-code-releases/latest" 2>/dev/null \
        | tr -d '[:space:]' > "$ccver_cache.tmp" 2>/dev/null \
        && mv "$ccver_cache.tmp" "$ccver_cache" 2>/dev/null; } &
fi
cc_latest=$(tr -d '[:space:]' < "$ccver_cache" 2>/dev/null)
cc_update=""
if [ -n "$cc_latest" ] && [ "$cc_latest" != "$version" ]; then
    newest=$(printf '%s\n%s\n' "$version" "$cc_latest" | sort -V | tail -1)
    [ "$newest" = "$cc_latest" ] && cc_update=1
fi

# Formatted values
ctx_used_f=$(fmt "$total_in"); ctx_total_f=$(fmt "$ctx_size")
in_f=$(fmt "$total_in"); out_f=$(fmt "$out_tok"); cache_f=$(fmt "$total_cache")
cost_f=$(printf '$%.2f' "$sess_cost")

# Reasoning effort: prefer the live session value from the payload (reflects
# /effort changes immediately); fall back to the persisted settings default.
effort=$(echo "$input" | jq -r '.effort.level // empty' 2>/dev/null)
[ -z "$effort" ] && effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
[ -z "$effort" ] || [ "$effort" = "null" ] && effort="off"
case "$effort" in
    max)     effort_color="$red" ;;
    xhigh)   effort_color="$orange" ;;
    high)    effort_color="$yellow" ;;
    medium)  effort_color="$green" ;;
    low)     effort_color="$white" ;;
    *)       effort_color="$dm" ;;   # none / off / unset
esac

# ═══════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════

# ── TOP BOX ──
box_line "┌" "┐"
printf "\n"

# Row 1: MODEL | CONTEXT
_begin
_label "MODEL";   _pad_to 9; _val "$model" "$blue"; _val " · " "$dm"; _val "$effort" "$effort_color"
_pad_to 56
_label "CONTEXT"; _gap 2; _val "${ctx_used_f} / ${ctx_total_f}" "$orange"; _val " (${ctx_pct_str}%)" "$green"
_emit; printf "\n"

# Row 2: PATH + branch | VERSION + update indicator
cur_dir=$(echo "$input" | jq -r '.workspace.current_dir // ""')
cur_dir="${cur_dir/#$HOME/~}"
# fit "path  branch" into the left column (cols 9..54)
avail=45
if [ -n "$git_info" ]; then pmax=$((avail - ${#git_info} - 2)); else pmax=$avail; fi
[ "$pmax" -lt 12 ] && pmax=12
[ ${#cur_dir} -gt "$pmax" ] && cur_dir="...${cur_dir: -$((pmax - 3))}"
_begin
_label "PATH";    _pad_to 9; _val "$cur_dir"
[ -n "$git_info" ] && { _gap 2; _val "$git_info" "$green"; }
_pad_to 56
_label "VERSION"; _gap 2; _val "$version" "$blue"
[ -n "$cc_update" ] && _val " ↑${cc_latest}" "$yellow"
_emit; printf "\n"

box_line "└" "┘"
exit 0
