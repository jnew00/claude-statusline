#!/bin/bash
# Claude Plan Usage Service Manager (Ubuntu/systemd)

SERVICE_NAME="claude-plan-usage"
SERVICE_FILE="/etc/systemd/user/claude-plan-usage.service"
LOG_PATH="$HOME/.claude/plan-usage.log"
ERROR_LOG_PATH="$HOME/.claude/plan-usage.error.log"
OUTPUT_PATH="$HOME/.claude/plan-usage.json"

case "$1" in
    start)
        echo "Starting claude-plan-usage service..."
        systemctl --user start $SERVICE_NAME
        sleep 1
        if systemctl --user is-active --quiet $SERVICE_NAME; then
            echo "✓ Service started"
        else
            echo "✗ Service failed to start. Check logs:"
            echo "  journalctl --user -u $SERVICE_NAME -n 20"
        fi
        ;;

    stop)
        echo "Stopping claude-plan-usage service..."
        systemctl --user stop $SERVICE_NAME
        echo "✓ Service stopped"
        ;;

    restart)
        echo "Restarting claude-plan-usage service..."
        systemctl --user restart $SERVICE_NAME
        sleep 1
        if systemctl --user is-active --quiet $SERVICE_NAME; then
            echo "✓ Service restarted"
        else
            echo "✗ Service failed to start"
        fi
        ;;

    status)
        if systemctl --user is-active --quiet $SERVICE_NAME; then
            echo "✓ Service is running"
            echo ""
            systemctl --user status $SERVICE_NAME | head -20
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
        echo "=== Recent systemd logs ==="
        journalctl --user -u $SERVICE_NAME -n 30
        ;;

    tail)
        journalctl --user -u $SERVICE_NAME -f
        ;;

    data)
        if [ -f "$OUTPUT_PATH" ]; then
            cat "$OUTPUT_PATH" | jq .
        else
            echo "No data file found at: $OUTPUT_PATH"
        fi
        ;;

    install)
        echo "Installing claude-plan-usage service..."

        # Create the service file
        SERVICE_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SERVICE_DIR"

        # Get the absolute path to the project
        PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

        cat > "$SERVICE_DIR/claude-plan-usage.service" << EOF
[Unit]
Description=Claude Plan Usage Fetcher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_PATH
ExecStart=$PROJECT_PATH/run.sh
Restart=on-failure
RestartSec=30

StandardOutput=journal
StandardError=journal
Environment="HOME=$HOME"

[Install]
WantedBy=default.target
EOF

        # Create the run.sh wrapper
        cat > "$PROJECT_PATH/run.sh" << 'RUNEOF'
#!/bin/bash
cd "$(dirname "$0")"
exec npm run daemon >> "$HOME/.claude/plan-usage.log" 2>> "$HOME/.claude/plan-usage.error.log"
RUNEOF
        chmod +x "$PROJECT_PATH/run.sh"

        # Reload systemd and enable
        systemctl --user daemon-reload
        systemctl --user enable $SERVICE_NAME

        echo "✓ Service installed"
        echo ""
        echo "To start the service, run:"
        echo "  ./manage-ubuntu.sh start"
        ;;

    uninstall)
        echo "Uninstalling claude-plan-usage service..."
        systemctl --user disable $SERVICE_NAME
        systemctl --user stop $SERVICE_NAME
        rm -f "$HOME/.config/systemd/user/claude-plan-usage.service"
        systemctl --user daemon-reload
        echo "✓ Service uninstalled"
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|logs|tail|data|install|uninstall}"
        echo ""
        echo "Commands:"
        echo "  start      - Start the service"
        echo "  stop       - Stop the service"
        echo "  restart    - Restart the service"
        echo "  status     - Check if service is running"
        echo "  logs       - Show recent logs"
        echo "  tail       - Follow logs in real-time"
        echo "  data       - Show current usage data"
        echo "  install    - Install service (run once)"
        echo "  uninstall  - Uninstall service"
        exit 1
        ;;
esac
