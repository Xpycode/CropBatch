#!/bin/bash
# Launch Directions documentation browser

cd "$(dirname "$0")"
PORT=8000

# Check if port is already in use
if lsof -i :$PORT > /dev/null 2>&1; then
    echo "Server already running on port $PORT"
    open "http://localhost:$PORT/docs-browser.html"
    exit 0
fi

echo "Starting documentation server on http://localhost:$PORT"
open "http://localhost:$PORT/docs-browser.html"
python3 -m http.server $PORT
