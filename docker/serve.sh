#!/bin/bash
# Simple HTTP server to serve plan-usage.json using Python

PORT=${HTTP_PORT:-8080}
OUTPUT_DIR=${OUTPUT_DIR:-/data/output}

echo "Serving ${OUTPUT_DIR} on port ${PORT}..."

# Create output dir and default file if needed
mkdir -p "${OUTPUT_DIR}"
if [ ! -f "${OUTPUT_DIR}/plan-usage.json" ]; then
    echo '{"error": "No data yet. Run scraper first.", "fetched_at": null}' > "${OUTPUT_DIR}/plan-usage.json"
fi

cd "${OUTPUT_DIR}"
python3 -m http.server ${PORT} --bind 0.0.0.0
