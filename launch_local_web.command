#!/bin/bash
set -e

# Use the folder where this launcher lives as the website root.
ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT=8000

cd "$ROOT"

echo
echo "=== LOCAL ARCHIVE SERVER ==="
echo "Root: $ROOT"
echo "URL:  http://localhost:$PORT/"
echo
echo "Keep this Terminal window open while editing."
echo "Press Ctrl+C to stop the server."
echo

# Open the editor after the server has had a moment to start.
(
  sleep 1
  open "http://localhost:$PORT/visual_archive_editor.html"
) &

python3 -m http.server "$PORT"
