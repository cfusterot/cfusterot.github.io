#!/bin/bash
set -uo pipefail

# ================================================================
# PREPARAR IMÁGENES DEL PORTFOLIO PARA GITHUB PAGES
#
# Estructura esperada:
#
#   repo/
#   ├── img_originales/     <- NO se sube a GitHub
#   ├── img/                <- copias web procesadas, SÍ se suben
#   ├── tools/photo-prep/
#   │   ├── Publicar_Imagenes_Web.command
#   │   └── proteger_caras.py
#   └── visual_archive.html
#
# Mantiene la estructura de subcarpetas de img_originales dentro de img.
# JPG/JPEG y PNG conservan su nombre de archivo para que los src del HTML
# puedan apuntar directamente a img/... sin pasos posteriores.
# ================================================================

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$REPO_ROOT/img_originales"
OUTPUT_DIR="$REPO_ROOT/img"

SUPPORT_DIR="$HOME/Library/Application Support/PreparadorFotosInternet"
FACE_VENV="$SUPPORT_DIR/venv-caras"
FACE_PYTHON="$FACE_VENV/bin/python"
FACE_HELPER="$SCRIPT_DIR/proteger_caras.py"

mkdir -p "$SUPPORT_DIR"

RUN_DATE="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG_FILE="$SUPPORT_DIR/GitHub_${RUN_DATE}.tsv"

show_error() {
  /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null
on run argv
  display alert "Portfolio · Preparar imágenes" message (item 1 of argv) as critical buttons {"Aceptar"} default button "Aceptar"
end run
APPLESCRIPT
}

choose_from_list() {
  local title="$1"
  local prompt="$2"
  shift 2
  local joined
  joined="$(printf '%s\n' "$@")"
  /usr/bin/osascript - "$title" "$prompt" "$joined" <<'APPLESCRIPT'
on run argv
  set theTitle to item 1 of argv
  set thePrompt to item 2 of argv
  set rawOptions to item 3 of argv
  set AppleScript's text item delimiters to linefeed
  set optionsList to text items of rawOptions
  set AppleScript's text item delimiters to ""
  set chosenItem to choose from list optionsList with title theTitle with prompt thePrompt default items {item 1 of optionsList} OK button name "Continuar" cancel button name "Cancelar"
  if chosenItem is false then return ""
  return item 1 of chosenItem
end run
APPLESCRIPT
}

ask_text() {
  local prompt="$1"
  local default_value="$2"
  /usr/bin/osascript - "$prompt" "$default_value" <<'APPLESCRIPT'
on run argv
  try
    set d to display dialog (item 1 of argv) default answer (item 2 of argv) with title "Portfolio · Preparar imágenes" buttons {"Cancelar", "Continuar"} default button "Continuar" cancel button "Cancelar"
    return text returned of d
  on error number -128
    return "__CANCEL__"
  end try
end run
APPLESCRIPT
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  show_error "Este script está preparado para macOS."
  exit 1
fi

if [[ ! -d "$SOURCE" ]]; then
  mkdir -p "$SOURCE"
  show_error "He creado la carpeta:

$SOURCE

Pon ahí los originales manteniendo las mismas subcarpetas que quieres publicar dentro de img/ y ejecuta de nuevo el script.

Esta carpeta debe permanecer fuera de Git."
  exit 0
fi

BREW_BIN=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [[ -x "$candidate" ]] && BREW_BIN="$candidate" && break
done

if [[ -z "$BREW_BIN" ]]; then
  show_error "No encuentro Homebrew. Instálalo desde brew.sh."
  exit 1
fi

ensure_brew_pkg() {
  local pkg="$1"
  local binary_rel="$2"
  local prefix
  prefix="$("$BREW_BIN" --prefix "$pkg" 2>/dev/null || true)"
  if [[ ! -x "$prefix/$binary_rel" ]]; then
    "$BREW_BIN" install "$pkg" || exit 1
    prefix="$("$BREW_BIN" --prefix "$pkg")"
  fi
  printf '%s' "$prefix/$binary_rel"
}

MAGICK_BIN="$(ensure_brew_pkg imagemagick bin/magick)"
EXIFTOOL_BIN="$(ensure_brew_pkg exiftool bin/exiftool)"

SIZE_CHOICE="$(choose_from_list \
  "Portfolio · Preparar imágenes" \
  "Tamaño máximo del lado más largo" \
  "1600 px — web ligera" \
  "2000 px — recomendado" \
  "2500 px — más detalle")"

case "$SIZE_CHOICE" in
  "1600 px — web ligera") MAX_SIZE=1600 ;;
  "2000 px — recomendado") MAX_SIZE=2000 ;;
  "2500 px — más detalle") MAX_SIZE=2500 ;;
  *) exit 0 ;;
esac

FACE_CHOICE="$(choose_from_list \
  "Portfolio · Preparar imágenes" \
  "Protección de caras" \
  "Sin modificar caras" \
  "Pixelar caras" \
  "Difuminar caras")"

case "$FACE_CHOICE" in
  "Sin modificar caras") FACE_MODE="none" ;;
  "Pixelar caras") FACE_MODE="pixelate" ;;
  "Difuminar caras") FACE_MODE="blur" ;;
  *) exit 0 ;;
esac

AUTHOR="$(ask_text "Autora/copyright (puedes dejarlo vacío)" "")"
[[ "$AUTHOR" == "__CANCEL__" ]] && exit 0

RIGHTS_TEXT="Todos los derechos reservados."
[[ -n "$AUTHOR" ]] && RIGHTS_TEXT="© $(date '+%Y') $AUTHOR. Todos los derechos reservados."
NO_AI_TEXT="No autorizado para entrenamiento de inteligencia artificial, aprendizaje automático, minería de datos ni generación de contenido derivado."

if [[ "$FACE_MODE" != "none" ]]; then
  PYTHON_PREFIX="$("$BREW_BIN" --prefix python@3.13 2>/dev/null || true)"
  PYTHON_BIN="$PYTHON_PREFIX/bin/python3.13"
  if [[ ! -x "$PYTHON_BIN" ]]; then
    "$BREW_BIN" install python@3.13 || exit 1
    PYTHON_PREFIX="$("$BREW_BIN" --prefix python@3.13)"
    PYTHON_BIN="$PYTHON_PREFIX/bin/python3.13"
  fi

  if [[ ! -x "$FACE_PYTHON" ]]; then
    "$PYTHON_BIN" -m venv "$FACE_VENV" || exit 1
    "$FACE_PYTHON" -m pip install --disable-pip-version-check --only-binary=:all: "opencv-python-headless==5.0.0.93" || exit 1
  fi
fi

mkdir -p "$OUTPUT_DIR"
printf "estado\torigen\tsalida\tdetalle\n" > "$LOG_FILE"

processed=0
failed=0

while IFS= read -r -d '' SOURCE_FILE; do
  REL="${SOURCE_FILE#$SOURCE/}"
  DIR="$(dirname "$REL")"
  NAME="$(basename "$REL")"
  EXT="${NAME##*.}"
  EXT_LOWER="$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')"

  case "$EXT_LOWER" in
    jpg|jpeg|png|webp|heic|heif|tif|tiff) ;;
    *) continue ;;
  esac

  if [[ "$DIR" == "." ]]; then
    DEST_DIR="$OUTPUT_DIR"
  else
    DEST_DIR="$OUTPUT_DIR/$DIR"
  fi
  mkdir -p "$DEST_DIR"

  STEM="${NAME%.*}"

  # Preserve website-friendly extensions where possible.
  case "$EXT_LOWER" in
    jpg|jpeg)
      OUT="$DEST_DIR/$NAME"
      FORMAT_KIND="jpeg"
      ;;
    png)
      OUT="$DEST_DIR/$NAME"
      FORMAT_KIND="png"
      ;;
    webp)
      OUT="$DEST_DIR/$NAME"
      FORMAT_KIND="webp"
      ;;
    *)
      OUT="$DEST_DIR/$STEM.jpg"
      FORMAT_KIND="jpeg"
      printf "AVISO: %s se publicará como %s\n" "$REL" "${OUT#$REPO_ROOT/}"
      ;;
  esac

  printf "Procesando: %s\n" "$REL"

  status=0

  case "$FORMAT_KIND" in
    jpeg)
      "$MAGICK_BIN" "$SOURCE_FILE" \
        -auto-orient \
        -resize "${MAX_SIZE}x${MAX_SIZE}>" \
        -colorspace sRGB \
        -background white -alpha remove -alpha off \
        -strip \
        -sampling-factor 4:2:0 \
        -interlace Plane \
        -quality 85 \
        "$OUT" || status=$?
      ;;
    png)
      # PNG preserves transparency, useful for future cut-out silhouettes.
      "$MAGICK_BIN" "$SOURCE_FILE" \
        -auto-orient \
        -resize "${MAX_SIZE}x${MAX_SIZE}>" \
        -colorspace sRGB \
        -strip \
        -define png:compression-level=8 \
        "$OUT" || status=$?
      ;;
    webp)
      "$MAGICK_BIN" "$SOURCE_FILE" \
        -auto-orient \
        -resize "${MAX_SIZE}x${MAX_SIZE}>" \
        -colorspace sRGB \
        -strip \
        -quality 84 \
        "$OUT" || status=$?
      ;;
  esac

  if [[ $status -ne 0 || ! -s "$OUT" ]]; then
    failed=$((failed + 1))
    printf "ERROR\t%s\t%s\tImageMagick\n" "$SOURCE_FILE" "$OUT" >> "$LOG_FILE"
    continue
  fi

  FACE_COUNT=0
  if [[ "$FACE_MODE" != "none" ]]; then
    FACE_RESULT="$("$FACE_PYTHON" "$FACE_HELPER" "$OUT" "$FACE_MODE" 2>/dev/null || true)"
    [[ "$FACE_RESULT" =~ ^[0-9]+$ ]] && FACE_COUNT="$FACE_RESULT"
  fi

  META_ARGS=(
    -overwrite_original
    -all=
    -TagsFromFile "$SOURCE_FILE"
    -DateTimeOriginal
    -CreateDate
    "-XMP-dc:Rights=$RIGHTS_TEXT"
    "-XMP-xmpRights:Marked=True"
    "-XMP-xmpRights:UsageTerms=$NO_AI_TEXT"
    "-IPTC:CopyrightNotice=$RIGHTS_TEXT"
    "-IPTC:SpecialInstructions=$NO_AI_TEXT"
  )

  if [[ -n "$AUTHOR" ]]; then
    META_ARGS+=("-Artist=$AUTHOR" "-XMP-dc:Creator=$AUTHOR" "-IPTC:By-line=$AUTHOR")
  fi

  "$EXIFTOOL_BIN" "${META_ARGS[@]}" "$OUT" >/dev/null 2>&1 || true

  printf "OK\t%s\t%s\tcaras modificadas: %s\n" "$SOURCE_FILE" "$OUT" "$FACE_COUNT" >> "$LOG_FILE"
  processed=$((processed + 1))

done < <(find "$SOURCE" -type f -print0)

osascript - "$processed" "$failed" "$OUTPUT_DIR" <<'APPLESCRIPT'
on run argv
  display dialog "Listo.

Procesadas: " & item 1 of argv & "
Errores: " & item 2 of argv & "

Copias web:
" & item 3 of argv & "

Solo la carpeta img/ debe subirse a GitHub. Conserva img_originales/ fuera de Git." with title "Portfolio · Preparar imágenes" buttons {"Aceptar"} default button "Aceptar"
end run
APPLESCRIPT

open "$OUTPUT_DIR"
