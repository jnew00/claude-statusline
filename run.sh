#!/bin/bash
cd "$(dirname "$0")"
exec npm run daemon >> "$HOME/.claude/plan-usage.log" 2>> "$HOME/.claude/plan-usage.error.log"
