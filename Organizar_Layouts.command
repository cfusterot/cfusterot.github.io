#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
LAYOUTS="$ROOT/layouts"
mkdir -p "$LAYOUTS"

FILES=(
  "source_layout.js"
  "visual_archive_layout.js"
  "visual_archive_layout_photo.js"
  "visual_archive_layout_video.js"
  "visual_archive_layout_escitalopram.js"
  "visual_archive_layout_backup.json"
)

echo
echo "=== ORGANIZAR LAYOUTS ==="
echo "Repositorio: $ROOT"
echo "Destino:     $LAYOUTS"
echo

for f in "${FILES[@]}"; do
  if [ -f "$ROOT/$f" ]; then
    mv "$ROOT/$f" "$LAYOUTS/$f"
    echo "movido: $f -> layouts/$f"
  fi
done

echo
echo "Listo. Los HTML deben usar rutas layouts/..."
