#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }

# Start Xvfb (virtual display)
start_xvfb() {
    log "Starting Xvfb on display :99..."
    Xvfb :99 -screen 0 1280x720x24 &
    XVFB_PID=$!
    sleep 2

    if ! kill -0 $XVFB_PID 2>/dev/null; then
        error "Failed to start Xvfb"
        exit 1
    fi
    log "Xvfb started (PID: $XVFB_PID)"
}

# Start VNC server for remote access (login mode only)
start_vnc() {
    log "Starting VNC server on port ${VNC_PORT} (no password)..."
    x11vnc -display :99 -forever -shared -nopw -rfbport ${VNC_PORT} -bg -o /tmp/x11vnc.log
    log "VNC server started. Connect to port ${VNC_PORT} to see the browser."
    log "  Example: open vnc://your-server-ip:${VNC_PORT}"
}

# Start HTTP server to serve the JSON file
start_http_server() {
    log "Starting HTTP server on port ${HTTP_PORT}..."
    ./serve.sh &
    HTTP_PID=$!
    log "HTTP server started (PID: $HTTP_PID)"
}

# Run the scraper
run_scraper() {
    log "Running scraper..."

    # Override paths for Docker environment
    export PLAYWRIGHT_PROFILE_DIR="${PROFILE_DIR}"

    node dist/claude-plan-usage.js "$@"

    # Copy output to served location
    if [ -f "$HOME/.claude/plan-usage.json" ]; then
        cp "$HOME/.claude/plan-usage.json" "${OUTPUT_DIR}/plan-usage.json"
        log "Output copied to ${OUTPUT_DIR}/plan-usage.json"
    fi
}

# Login mode - opens browser with VNC access
login_mode() {
    log "=== LOGIN MODE ==="
    log ""
    log "This mode opens a browser for manual login."
    log "Connect via VNC to see and interact with the browser."
    log ""

    start_xvfb
    start_vnc

    log ""
    log "=========================================="
    log "  VNC server ready on port ${VNC_PORT}"
    log "  Connect with: vnc://your-server:${VNC_PORT}"
    log "=========================================="
    log ""

    # Create .claude directory
    mkdir -p "$HOME/.claude"

    # Run in login mode
    run_scraper --login

    log "Login complete! Session saved to ${PROFILE_DIR}"
}

# Scrape mode - runs scraper and serves result
scrape_mode() {
    log "=== SCRAPE MODE ==="

    # Check if we have a saved session
    if [ ! -d "${PROFILE_DIR}" ] || [ -z "$(ls -A ${PROFILE_DIR} 2>/dev/null)" ]; then
        warn "No saved session found. Run with 'login' first."
        warn "  docker run -it --rm -p 5900:5900 -v data:/data claude-scraper login"
        exit 1
    fi

    start_xvfb

    # Create .claude directory and symlink profile
    mkdir -p "$HOME/.claude"
    ln -sf "${PROFILE_DIR}" "$HOME/.claude/playwright-profile"

    run_scraper
}

# Serve mode - just run HTTP server
serve_mode() {
    log "=== SERVE MODE ==="
    start_http_server

    # Keep container running
    wait $HTTP_PID
}

# Daemon mode - scrape periodically and serve
daemon_mode() {
    log "=== DAEMON MODE ==="

    INTERVAL=${SCRAPE_INTERVAL:-600}  # Default 10 minutes

    start_xvfb
    start_http_server

    # Create .claude directory and symlink profile
    mkdir -p "$HOME/.claude"
    ln -sf "${PROFILE_DIR}" "$HOME/.claude/playwright-profile"

    log "Starting daemon with ${INTERVAL}s interval..."

    while true; do
        log "Running scheduled scrape..."
        run_scraper || warn "Scrape failed, will retry next interval"
        log "Sleeping for ${INTERVAL}s..."
        sleep $INTERVAL
    done
}

# Main command handler
case "${1:-scrape}" in
    login)
        login_mode
        ;;
    scrape)
        scrape_mode
        ;;
    serve)
        serve_mode
        ;;
    daemon)
        daemon_mode
        ;;
    *)
        echo "Usage: $0 {login|scrape|serve|daemon}"
        echo ""
        echo "Commands:"
        echo "  login   - Open browser for manual login (use VNC to interact)"
        echo "  scrape  - Run scraper once and exit"
        echo "  serve   - Just serve the JSON file via HTTP"
        echo "  daemon  - Run scraper periodically and serve results"
        echo ""
        echo "Environment variables:"
        echo "  SCRAPE_INTERVAL - Seconds between scrapes in daemon mode (default: 600)"
        echo "  HTTP_PORT       - Port for HTTP server (default: 8080)"
        echo "  VNC_PORT        - Port for VNC server (default: 5900)"
        exit 1
        ;;
esac
