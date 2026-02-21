#!/bin/sh
set -e

# On first run the mounted /app/data will be empty — seed from built-in data
if [ ! -d /app/data/fhir ] || [ -z "$(ls -A /app/data/fhir 2>/dev/null)" ]; then
  echo "Seeding data directory from built-in defaults..."
  cp -a /app/data-seed/. /app/data/
fi

# Wait for server to be ready in the background, then print banner
(
  while ! python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/health')" 2>/dev/null; do
    sleep 1
  done
  PORT="${DOCGEMMA_PORT:-8080}"
  echo ""
  echo "  DocGemma is live at http://localhost:${PORT}"
  echo ""
) &

exec "$@"
