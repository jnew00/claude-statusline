#!/bin/bash
# Claude Plan Usage Service Manager

PLIST_NAME="com.claude.plan-usage"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
LOG_PATH="$HOME/.claude/plan-usage.log"
ERROR_LOG_PATH="$HOME/.claude/plan-usage.error.log"
OUTPUT_PATH="$HOME/.claude/plan-usage.json"

case "$1" in
    start)
        echo "Starting claude-plan-usage service..."
        launchctl load "$PLIST_PATH"
        sleep 1
        if pgrep -f "claude-plan-usage.js" > /dev/null; then
            echo "✓ Service started"
        else
            echo "✗ Service failed to start. Check logs:"
            echo "  tail -f $ERROR_LOG_PATH"
        fi
        ;;

    stop)
        echo "Stopping claude-plan-usage service..."
        launchctl unload "$PLIST_PATH"
        echo "✓ Service stopped"
        ;;

    restart)
        echo "Restarting claude-plan-usage service..."
        launchctl unload "$PLIST_PATH" 2>/dev/null || true
        sleep 1
        launchctl load "$PLIST_PATH"
        sleep 1
        if pgrep -f "claude-plan-usage.js" > /dev/null; then
            echo "✓ Service restarted"
        else
            echo "✗ Service failed to start"
        fi
        ;;

    status)
        if pgrep -f "claude-plan-usage.js" > /dev/null; then
            echo "✓ Service is running"
            echo ""
            ps aux | grep "claude-plan-usage.js" | grep -v grep
            echo ""
            if [ -f "$OUTPUT_PATH" ]; then
                echo "Latest data:"
                jq '{five_hour: .five_hour_percent, weekly: .weekly_percent, resets_in: .resets_in, fetched: .fetched_at}' "$OUTPUT_PATH"
            fi
        else
            echo "✗ Service is not running"
        fi
        ;;

    logs)
        echo "=== Output Log ==="
        tail -20 "$LOG_PATH"
        echo ""
        echo "=== Error Log ==="
        tail -20 "$ERROR_LOG_PATH" 2>/dev/null || echo "(no errors)"
        ;;

    tail)
        tail -f "$LOG_PATH"
        ;;

    data)
        if [ -f "$OUTPUT_PATH" ]; then
            cat "$OUTPUT_PATH" | jq .
        else
            echo "No data file found at: $OUTPUT_PATH"
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|logs|tail|data}"
        echo ""
        echo "Commands:"
        echo "  start    - Start the service"
        echo "  stop     - Stop the service"
        echo "  restart  - Restart the service"
        echo "  status   - Check if service is running"
        echo "  logs     - Show recent logs"
        echo "  tail     - Follow logs in real-time"
        echo "  data     - Show current usage data"
        exit 1
        ;;
esac
