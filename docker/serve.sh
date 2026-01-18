#!/bin/bash
# Simple HTTP server to serve plan-usage.json
# Uses netcat for minimal dependencies

PORT=${HTTP_PORT:-8080}
OUTPUT_DIR=${OUTPUT_DIR:-/data/output}
JSON_FILE="${OUTPUT_DIR}/plan-usage.json"

echo "Serving ${JSON_FILE} on port ${PORT}..."

# Create a default response if file doesn't exist
create_default_json() {
    echo '{"error": "No data yet. Run scraper first.", "fetched_at": null}'
}

while true; do
    # Handle HTTP request
    {
        # Read request (just need first line)
        read -r request_line

        # Parse request
        method=$(echo "$request_line" | cut -d' ' -f1)
        path=$(echo "$request_line" | cut -d' ' -f2)

        # Read headers (discard them)
        while read -r header; do
            [ -z "$header" ] || [ "$header" = $'\r' ] && break
        done

        # Route handling
        case "$path" in
            /plan-usage.json|/)
                if [ -f "$JSON_FILE" ]; then
                    content=$(cat "$JSON_FILE")
                    status="200 OK"
                else
                    content=$(create_default_json)
                    status="200 OK"
                fi
                content_type="application/json"
                ;;
            /health)
                content='{"status": "ok"}'
                status="200 OK"
                content_type="application/json"
                ;;
            *)
                content='{"error": "Not found"}'
                status="404 Not Found"
                content_type="application/json"
                ;;
        esac

        # Calculate content length
        content_length=${#content}

        # Send response
        echo -e "HTTP/1.1 ${status}\r"
        echo -e "Content-Type: ${content_type}\r"
        echo -e "Content-Length: ${content_length}\r"
        echo -e "Access-Control-Allow-Origin: *\r"
        echo -e "Connection: close\r"
        echo -e "\r"
        echo -n "$content"

    } | nc -l -p $PORT -q 1 2>/dev/null || {
        # If nc doesn't support -q, try without it
        {
            read -r request_line
            while read -r header; do
                [ -z "$header" ] || [ "$header" = $'\r' ] && break
            done

            if [ -f "$JSON_FILE" ]; then
                content=$(cat "$JSON_FILE")
            else
                content=$(create_default_json)
            fi

            echo -e "HTTP/1.1 200 OK\r"
            echo -e "Content-Type: application/json\r"
            echo -e "Access-Control-Allow-Origin: *\r"
            echo -e "Connection: close\r"
            echo -e "\r"
            echo -n "$content"
        } | nc -l -p $PORT
    }
done
