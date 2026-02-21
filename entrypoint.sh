#!/bin/sh
set -e

# On first run the mounted /app/data will be empty — seed from built-in data
if [ ! -d /app/data/fhir ] || [ -z "$(ls -A /app/data/fhir 2>/dev/null)" ]; then
  echo "Seeding data directory from built-in defaults..."
  cp -a /app/data-seed/. /app/data/
fi

exec "$@"
