#!/bin/bash
# Claude Code StatusLine - single line: MODEL · CONTEXT · EFFORT
# Single-line to sidestep cli-truncate regression in v2.1.112+ (issue #37522)

input=$(cat)
[ -z "$input" ] && { printf "Claude"; exit 0; }

e=$'\033'
blue="${e}[38;2;80;180;255m"
orange="${e}[38;2;255;200;100m"
green="${e}[38;2;50;230;50m"
red="${e}[38;2;255;100;100m"
white="${e}[38;2;240;240;240m"
dm="${e}[2m"
rs="${e}[0m"

fmt() {
    local n=$1; [ "$n" = "null" ] && n=0
    if [ "$n" -ge 1000000 ] 2>/dev/null; then
        printf "%.1fM" "$(echo "scale=1; $n/1000000" | bc)"
    elif [ "$n" -ge 1000 ] 2>/dev/null; then
        printf "%.1fk" "$(echo "scale=1; $n/1000" | bc)"
    else printf "%d" "$n"; fi
}

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$ctx_size" = "null" ] || [ -z "$ctx_size" ] && ctx_size=200000

in_tok=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cc_tok=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cr_tok=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
[ "$in_tok" = "null" ] && in_tok=0
[ "$cc_tok" = "null" ] && cc_tok=0
[ "$cr_tok" = "null" ] && cr_tok=0

total_in=$((in_tok + cc_tok + cr_tok))
ctx_pct_str=$(printf "%.1f" "$(echo "scale=1; $total_in * 100 / $ctx_size" | bc 2>/dev/null)" 2>/dev/null || echo "0.0")
ctx_pct_int=${ctx_pct_str%.*}

if   [ "$ctx_pct_int" -ge 90 ] 2>/dev/null; then pct_color="$red"
elif [ "$ctx_pct_int" -ge 70 ] 2>/dev/null; then pct_color="$orange"
else pct_color="$green"; fi

effort="off"; effort_color="$dm"
if [ -f "$HOME/.claude/settings.json" ]; then
    effort=$(jq -r '.effortLevel // "off"' "$HOME/.claude/settings.json" 2>/dev/null)
    case "$effort" in
        high)    effort_color="$red" ;;
        medium)  effort_color="$orange" ;;
        low|minimal) effort_color="$white" ;;
        *)       effort_color="$dm" ;;
    esac
fi

ctx_used_f=$(fmt "$total_in")
ctx_total_f=$(fmt "$ctx_size")
sep="${dm} · ${rs}"

printf "%s%s%s%s%s%s / %s%s %s(%s%%)%s%seffort %s%s%s" \
    "$blue" "$model" "$rs" \
    "$sep" \
    "$white" "$ctx_used_f" "$ctx_total_f" "$rs" \
    "$pct_color" "$ctx_pct_str" "$rs" \
    "$sep" \
    "$effort_color" "$effort" "$rs"
