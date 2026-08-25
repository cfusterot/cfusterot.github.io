#!/bin/bash

set -uo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

APP_NAME="Preparador de Fotos para Internet"
APP_VERSION="1.1"
SUPPORT_DIR="$HOME/Library/Application Support/PreparadorFotosInternet"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DATE="$(date '+%Y-%m-%d_%H-%M-%S')"
DIAGNOSTIC_FILE="$SUPPORT_DIR/Diagnostico_${RUN_DATE}.txt"
FACE_VENV="$SUPPORT_DIR/venv-caras"
FACE_PYTHON="$FACE_VENV/bin/python"
FACE_HELPER="$SCRIPT_DIR/proteger_caras.py"

mkdir -p "$SUPPORT_DIR" || exit 1

show_error() {
  /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null
on run argv
  display alert "Preparador de Fotos para Internet" message (item 1 of argv) as critical buttons {"Aceptar"} default button "Aceptar"
end run
APPLESCRIPT
}

show_info() {
  /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null
on run argv
  display dialog (item 1 of argv) with title "Preparador de Fotos para Internet" buttons {"Aceptar"} default button "Aceptar"
end run
APPLESCRIPT
}

pause_terminal() {
  printf "\nPulsa Intro para cerrar esta ventana.\n"
  read -r _
}

fail() {
  local message="$1"
  printf "ERROR: %s\n" "$message" | tee -a "$DIAGNOSTIC_FILE"
  show_error "$message

No se ha modificado ninguna fotografía original.
Diagnóstico: $DIAGNOSTIC_FILE"
  pause_terminal
  exit 1
}

choose_folder() {
  local prompt="$1"
  /usr/bin/osascript - "$prompt" <<'APPLESCRIPT'
on run argv
  try
    set chosenFolder to choose folder with prompt (item 1 of argv)
    return POSIX path of chosenFolder
  on error number -128
    return ""
  end try
end run
APPLESCRIPT
}

choose_mode() {
  /usr/bin/osascript <<'APPLESCRIPT'
set optionsList to {"Crear copias web protegidas", "Preparar PNG para Glaze", "Finalizar imágenes después de Glaze"}
set chosenItem to choose from list optionsList with title "Preparador de Fotos para Internet" with prompt "¿Qué quieres hacer?" default items {"Crear copias web protegidas"} OK button name "Continuar" cancel button name "Cancelar"
if chosenItem is false then return ""
return item 1 of chosenItem
APPLESCRIPT
}

ask_text() {
  local prompt="$1"
  local default_value="$2"
  /usr/bin/osascript - "$prompt" "$default_value" <<'APPLESCRIPT'
on run argv
  try
    set answerDialog to display dialog (item 1 of argv) default answer (item 2 of argv) with title "Preparador de Fotos para Internet" buttons {"Cancelar", "Continuar"} default button "Continuar" cancel button "Cancelar"
    return text returned of answerDialog
  on error number -128
    return "__CANCEL__"
  end try
end run
APPLESCRIPT
}

choose_size() {
  /usr/bin/osascript <<'APPLESCRIPT'
set optionsList to {"1600 px — web ligera", "2000 px — recomendado", "2500 px — más detalle"}
set chosenItem to choose from list optionsList with title "Preparador de Fotos para Internet" with prompt "Tamaño máximo del lado más largo" default items {"2000 px — recomendado"} OK button name "Continuar" cancel button name "Cancelar"
if chosenItem is false then return ""
return item 1 of chosenItem
APPLESCRIPT
}

choose_watermark() {
  /usr/bin/osascript <<'APPLESCRIPT'
set optionsList to {"Discreta abajo a la derecha", "Visible en el centro", "Sin marca visible"}
set chosenItem to choose from list optionsList with title "Preparador de Fotos para Internet" with prompt "Marca de agua" default items {"Discreta abajo a la derecha"} OK button name "Continuar" cancel button name "Cancelar"
if chosenItem is false then return ""
return item 1 of chosenItem
APPLESCRIPT
}

choose_face_mode() {
  /usr/bin/osascript <<'APPLESCRIPT'
set optionsList to {"Sin modificar caras", "Pixelar caras — protección más fuerte", "Difuminar caras — resultado más suave"}
set chosenItem to choose from list optionsList with title "Preparador de Fotos para Internet" with prompt "¿Quieres ocultar las caras que detecte el programa?" default items {"Sin modificar caras"} OK button name "Continuar" cancel button name "Cancelar"
if chosenItem is false then return ""
return item 1 of chosenItem
APPLESCRIPT
}

safe_log_value() {
  printf '%s' "$1" | /usr/bin/tr '\t\r\n' '   '
}

{
  printf "Aplicación: %s %s\n" "$APP_NAME" "$APP_VERSION"
  printf "Fecha: %s\n" "$(date)"
  printf "macOS: %s\n" "$(/usr/bin/sw_vers -productVersion 2>/dev/null || true)"
  printf "Arquitectura: %s\n" "$(/usr/bin/uname -m)"
} > "$DIAGNOSTIC_FILE"

if [[ "$(/usr/bin/uname -s)" != "Darwin" ]]; then
  fail "Este programa solo funciona en macOS."
fi

printf "\n%s\n" "$APP_NAME"
printf "========================================\n\n"
printf "Crea copias para publicar. Los originales nunca se modifican ni se borran.\n\n"

BREW_BIN=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -x "$candidate" ]]; then
    BREW_BIN="$candidate"
    break
  fi
done

if [[ -z "$BREW_BIN" ]]; then
  fail "No encuentro Homebrew. Instálalo desde https://brew.sh y abre de nuevo este programa."
fi

MAGICK_PREFIX="$($BREW_BIN --prefix imagemagick 2>/dev/null || true)"
MAGICK_BIN="$MAGICK_PREFIX/bin/magick"
if [[ ! -x "$MAGICK_BIN" ]]; then
  printf "Instalando ImageMagick con Homebrew (solo la primera vez)...\n"
  if ! "$BREW_BIN" install imagemagick 2>&1 | tee -a "$DIAGNOSTIC_FILE"; then
    fail "No se ha podido instalar ImageMagick. Comprueba Internet y ejecuta: brew install imagemagick"
  fi
  MAGICK_PREFIX="$($BREW_BIN --prefix imagemagick 2>/dev/null || true)"
  MAGICK_BIN="$MAGICK_PREFIX/bin/magick"
fi

EXIFTOOL_PREFIX="$($BREW_BIN --prefix exiftool 2>/dev/null || true)"
EXIFTOOL_BIN="$EXIFTOOL_PREFIX/bin/exiftool"
if [[ ! -x "$EXIFTOOL_BIN" ]]; then
  printf "Instalando ExifTool con Homebrew (solo la primera vez)...\n"
  if ! "$BREW_BIN" install exiftool 2>&1 | tee -a "$DIAGNOSTIC_FILE"; then
    fail "No se ha podido instalar ExifTool. Comprueba Internet y ejecuta: brew install exiftool"
  fi
  EXIFTOOL_PREFIX="$($BREW_BIN --prefix exiftool 2>/dev/null || true)"
  EXIFTOOL_BIN="$EXIFTOOL_PREFIX/bin/exiftool"
fi

if [[ ! -x "$MAGICK_BIN" ]] || [[ ! -x "$EXIFTOOL_BIN" ]]; then
  fail "Falta alguno de los componentes necesarios."
fi

printf "ImageMagick: %s\n" "$($MAGICK_BIN -version 2>/dev/null | head -n 1)" >> "$DIAGNOSTIC_FILE"
printf "ExifTool: %s\n" "$($EXIFTOOL_BIN -ver 2>/dev/null || true)" >> "$DIAGNOSTIC_FILE"

MODE="$(choose_mode)"
if [[ -z "$MODE" ]]; then
  printf "Operación cancelada.\n"
  exit 0
fi

SOURCE="$(choose_folder "Elige la carpeta que contiene las imágenes originales")"
if [[ -z "$SOURCE" ]]; then
  printf "Operación cancelada.\n"
  exit 0
fi
SOURCE="${SOURCE%/}"

DEST_PARENT="$(choose_folder "Elige dónde guardar las copias preparadas")"
if [[ -z "$DEST_PARENT" ]]; then
  printf "Operación cancelada.\n"
  exit 0
fi
DEST_PARENT="${DEST_PARENT%/}"

SIZE_CHOICE="$(choose_size)"
case "$SIZE_CHOICE" in
  "1600 px — web ligera") MAX_SIZE="1600" ;;
  "2000 px — recomendado") MAX_SIZE="2000" ;;
  "2500 px — más detalle") MAX_SIZE="2500" ;;
  *) printf "Operación cancelada.\n"; exit 0 ;;
esac

AUTHOR="$(ask_text "Nombre de autora o copyright. Puedes dejarlo vacío." "")"
if [[ "$AUTHOR" == "__CANCEL__" ]]; then
  printf "Operación cancelada.\n"
  exit 0
fi

WATERMARK_MODE="Sin marca visible"
WATERMARK_TEXT=""

case "$MODE" in
  "Crear copias web protegidas")
    OUTPUT_DIR="$DEST_PARENT/Fotos_para_Internet"
    WATERMARK_MODE="$(choose_watermark)"
    ;;
  "Preparar PNG para Glaze")
    OUTPUT_DIR="$DEST_PARENT/PNG_para_Glaze"
    ;;
  "Finalizar imágenes después de Glaze")
    OUTPUT_DIR="$DEST_PARENT/Fotos_Glaze_para_Internet"
    WATERMARK_MODE="$(choose_watermark)"
    ;;
  *)
    printf "Operación cancelada.\n"
    exit 0
    ;;
esac

if [[ -z "$WATERMARK_MODE" ]]; then
  printf "Operación cancelada.\n"
  exit 0
fi

if [[ "$WATERMARK_MODE" != "Sin marca visible" ]]; then
  DEFAULT_WATERMARK="© $AUTHOR"
  if [[ -z "$AUTHOR" ]]; then
    DEFAULT_WATERMARK="© Todos los derechos reservados"
  fi
  WATERMARK_TEXT="$(ask_text "Texto de la marca de agua" "$DEFAULT_WATERMARK")"
  if [[ "$WATERMARK_TEXT" == "__CANCEL__" ]]; then
    printf "Operación cancelada.\n"
    exit 0
  fi
fi

FACE_CHOICE="$(choose_face_mode)"
case "$FACE_CHOICE" in
  "Sin modificar caras") FACE_MODE="none" ;;
  "Pixelar caras — protección más fuerte") FACE_MODE="pixelate" ;;
  "Difuminar caras — resultado más suave") FACE_MODE="blur" ;;
  *) printf "Operación cancelada.\n"; exit 0 ;;
esac

if [[ "$FACE_MODE" != "none" ]]; then
  if [[ ! -f "$FACE_HELPER" ]]; then
    fail "No encuentro el componente local de protección facial. Vuelve a descomprimir el ZIP completo."
  fi

  PYTHON_PREFIX="$($BREW_BIN --prefix python@3.13 2>/dev/null || true)"
  PYTHON_BIN="$PYTHON_PREFIX/bin/python3.13"
  if [[ ! -x "$PYTHON_BIN" ]]; then
    printf "Instalando Python 3.13 para la detección facial (solo la primera vez)...\n"
    if ! "$BREW_BIN" install python@3.13 2>&1 | tee -a "$DIAGNOSTIC_FILE"; then
      fail "No se ha podido instalar Python 3.13 para la detección facial."
    fi
    PYTHON_PREFIX="$($BREW_BIN --prefix python@3.13 2>/dev/null || true)"
    PYTHON_BIN="$PYTHON_PREFIX/bin/python3.13"
  fi

  if [[ ! -x "$FACE_PYTHON" ]]; then
    printf "Preparando el detector facial local (solo la primera vez; puede tardar unos minutos)...\n"
    if ! "$PYTHON_BIN" -m venv "$FACE_VENV" 2>&1 | tee -a "$DIAGNOSTIC_FILE"; then
      fail "No se ha podido crear el entorno del detector facial."
    fi
    if ! "$FACE_PYTHON" -m pip install --disable-pip-version-check --only-binary=:all: "opencv-python-headless==5.0.0.93" 2>&1 | tee -a "$DIAGNOSTIC_FILE"; then
      fail "No se ha podido instalar el detector facial compatible con Apple Silicon."
    fi
  fi

  if ! "$FACE_PYTHON" -c 'import cv2' >> "$DIAGNOSTIC_FILE" 2>&1; then
    fail "El detector facial se instaló, pero no puede iniciarse."
  fi
fi

if [[ "$OUTPUT_DIR" == "$SOURCE" ]] || [[ "$OUTPUT_DIR" == "$SOURCE/"* ]]; then
  fail "La carpeta de salida no puede estar dentro de la carpeta de origen. Elige otro destino para evitar procesar las copias de nuevo."
fi

if ! /bin/mkdir -p "$OUTPUT_DIR" 2>> "$DIAGNOSTIC_FILE"; then
  fail "No puedo crear la carpeta de salida. Revisa los permisos del disco en Privacidad y seguridad > Archivos y carpetas > Terminal."
fi

WRITE_TEST="$OUTPUT_DIR/.prueba_escritura_$$"
if ! printf 'prueba\n' > "$WRITE_TEST" 2>> "$DIAGNOSTIC_FILE"; then
  fail "macOS no permite escribir en el destino. Da permiso a Terminal para acceder al disco o volumen extraíble."
fi
/bin/rm "$WRITE_TEST" 2>/dev/null || true

LOG_FILE="$OUTPUT_DIR/Registro_${RUN_DATE}.tsv"
printf "estado\torigen\tsalida\tdetalle\n" > "$LOG_FILE"

RIGHTS_TEXT="Todos los derechos reservados."
if [[ -n "$AUTHOR" ]]; then
  RIGHTS_TEXT="© $(date '+%Y') $AUTHOR. Todos los derechos reservados."
fi
NO_AI_TEXT="No autorizado para entrenamiento de inteligencia artificial, aprendizaje automático, minería de datos ni generación de contenido derivado."

printf "\nModo: %s\n" "$MODE"
printf "Origen: %s\n" "$SOURCE"
printf "Destino: %s\n" "$OUTPUT_DIR"
printf "Tamaño máximo: %s px\n\n" "$MAX_SIZE"
printf "Tratamiento de caras: %s\n\n" "$FACE_CHOICE"

PROCESSED=0
FAILED=0
WARNINGS=0

while IFS= read -r -d '' SOURCE_FILE; do
  RELATIVE_PATH="${SOURCE_FILE#$SOURCE/}"
  RELATIVE_DIR="$(/usr/bin/dirname "$RELATIVE_PATH")"
  ORIGINAL_NAME="$(/usr/bin/basename "$RELATIVE_PATH")"
  EXTENSION="${ORIGINAL_NAME##*.}"
  EXTENSION_LOWER="$(printf '%s' "$EXTENSION" | /usr/bin/tr '[:upper:]' '[:lower:]')"

  case "$EXTENSION_LOWER" in
    jpg|jpeg|png|heic|heif|tif|tiff|webp) ;;
    *) continue ;;
  esac

  if [[ "$RELATIVE_DIR" == "." ]]; then
    ITEM_OUTPUT_DIR="$OUTPUT_DIR"
  else
    ITEM_OUTPUT_DIR="$OUTPUT_DIR/$RELATIVE_DIR"
  fi
  /bin/mkdir -p "$ITEM_OUTPUT_DIR" || {
    FAILED=$((FAILED + 1))
    printf "ERROR\t%s\t\tNo se pudo crear la subcarpeta\n" "$(safe_log_value "$SOURCE_FILE")" >> "$LOG_FILE"
    continue
  }

  if [[ "$MODE" == "Preparar PNG para Glaze" ]]; then
    OUTPUT_FILE="$ITEM_OUTPUT_DIR/${ORIGINAL_NAME}.png"
  else
    OUTPUT_FILE="$ITEM_OUTPUT_DIR/${ORIGINAL_NAME}.web.jpg"
  fi

  printf "Procesando: %s\n" "$RELATIVE_PATH"

  IMAGE_STATUS=0
  if [[ "$MODE" == "Preparar PNG para Glaze" ]]; then
    "$MAGICK_BIN" "$SOURCE_FILE" \
      -auto-orient \
      -resize "${MAX_SIZE}x${MAX_SIZE}>" \
      -colorspace sRGB \
      -strip \
      "$OUTPUT_FILE" >> "$DIAGNOSTIC_FILE" 2>&1 || IMAGE_STATUS=$?
  elif [[ "$FACE_MODE" == "none" ]] && [[ "$WATERMARK_MODE" == "Discreta abajo a la derecha" ]]; then
    "$MAGICK_BIN" "$SOURCE_FILE" \
      -auto-orient \
      -resize "${MAX_SIZE}x${MAX_SIZE}>" \
      -colorspace sRGB \
      -background white -alpha remove -alpha off \
      -strip \
      -gravity southeast -font Helvetica -pointsize 28 \
      -fill 'rgba(255,255,255,0.62)' -stroke 'rgba(0,0,0,0.42)' -strokewidth 1 \
      -annotate +28+22 "$WATERMARK_TEXT" \
      -sampling-factor 4:2:0 -interlace Plane -quality 85 \
      "$OUTPUT_FILE" >> "$DIAGNOSTIC_FILE" 2>&1 || IMAGE_STATUS=$?
  elif [[ "$FACE_MODE" == "none" ]] && [[ "$WATERMARK_MODE" == "Visible en el centro" ]]; then
    "$MAGICK_BIN" "$SOURCE_FILE" \
      -auto-orient \
      -resize "${MAX_SIZE}x${MAX_SIZE}>" \
      -colorspace sRGB \
      -background white -alpha remove -alpha off \
      -strip \
      -gravity center -font Helvetica -pointsize 46 \
      -fill 'rgba(255,255,255,0.48)' -stroke 'rgba(0,0,0,0.38)' -strokewidth 1 \
      -annotate +0+0 "$WATERMARK_TEXT" \
      -sampling-factor 4:2:0 -interlace Plane -quality 85 \
      "$OUTPUT_FILE" >> "$DIAGNOSTIC_FILE" 2>&1 || IMAGE_STATUS=$?
  else
    "$MAGICK_BIN" "$SOURCE_FILE" \
      -auto-orient \
      -resize "${MAX_SIZE}x${MAX_SIZE}>" \
      -colorspace sRGB \
      -background white -alpha remove -alpha off \
      -strip \
      -sampling-factor 4:2:0 -interlace Plane -quality 85 \
      "$OUTPUT_FILE" >> "$DIAGNOSTIC_FILE" 2>&1 || IMAGE_STATUS=$?
  fi

  if [[ $IMAGE_STATUS -ne 0 ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
    FAILED=$((FAILED + 1))
    printf "ERROR\t%s\t%s\tImageMagick no pudo procesar la imagen\n" \
      "$(safe_log_value "$SOURCE_FILE")" "$(safe_log_value "$OUTPUT_FILE")" >> "$LOG_FILE"
    continue
  fi

  FACE_COUNT="0"
  FACE_WARNING=""
  if [[ "$FACE_MODE" != "none" ]]; then
    FACE_RESULT="$($FACE_PYTHON "$FACE_HELPER" "$OUTPUT_FILE" "$FACE_MODE" 2>> "$DIAGNOSTIC_FILE")"
    FACE_STATUS=$?
    if [[ $FACE_STATUS -ne 0 ]]; then
      WARNINGS=$((WARNINGS + 1))
      FACE_WARNING="El detector facial falló; revisa esta imagen"
    elif [[ ! "$FACE_RESULT" =~ ^[0-9]+$ ]]; then
      WARNINGS=$((WARNINGS + 1))
      FACE_WARNING="El detector facial devolvió un resultado inesperado; revisa esta imagen"
    else
      FACE_COUNT="$FACE_RESULT"
    fi
  fi

  # Cuando se modifican caras, la marca se añade después para no dificultar
  # la detección, sobre todo si la marca central cruza un rostro.
  if [[ "$FACE_MODE" != "none" ]] && [[ "$MODE" != "Preparar PNG para Glaze" ]] && [[ "$WATERMARK_MODE" != "Sin marca visible" ]]; then
    WATERMARK_TEMP="$OUTPUT_FILE.marca.jpg"
    WATERMARK_STATUS=0
    if [[ "$WATERMARK_MODE" == "Discreta abajo a la derecha" ]]; then
      "$MAGICK_BIN" "$OUTPUT_FILE" \
        -gravity southeast -font Helvetica -pointsize 28 \
        -fill 'rgba(255,255,255,0.62)' -stroke 'rgba(0,0,0,0.42)' -strokewidth 1 \
        -annotate +28+22 "$WATERMARK_TEXT" \
        -sampling-factor 4:2:0 -interlace Plane -quality 85 \
        "$WATERMARK_TEMP" >> "$DIAGNOSTIC_FILE" 2>&1 || WATERMARK_STATUS=$?
    else
      "$MAGICK_BIN" "$OUTPUT_FILE" \
        -gravity center -font Helvetica -pointsize 46 \
        -fill 'rgba(255,255,255,0.48)' -stroke 'rgba(0,0,0,0.38)' -strokewidth 1 \
        -annotate +0+0 "$WATERMARK_TEXT" \
        -sampling-factor 4:2:0 -interlace Plane -quality 85 \
        "$WATERMARK_TEMP" >> "$DIAGNOSTIC_FILE" 2>&1 || WATERMARK_STATUS=$?
    fi
    if [[ $WATERMARK_STATUS -eq 0 ]] && [[ -s "$WATERMARK_TEMP" ]]; then
      /bin/mv "$WATERMARK_TEMP" "$OUTPUT_FILE"
    else
      /bin/rm "$WATERMARK_TEMP" 2>/dev/null || true
      WARNINGS=$((WARNINGS + 1))
      if [[ -n "$FACE_WARNING" ]]; then
        FACE_WARNING="$FACE_WARNING; la marca de agua no pudo añadirse"
      else
        FACE_WARNING="La marca de agua no pudo añadirse"
      fi
    fi
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

  if ! "$EXIFTOOL_BIN" "${META_ARGS[@]}" "$OUTPUT_FILE" >> "$DIAGNOSTIC_FILE" 2>&1; then
    WARNINGS=$((WARNINGS + 1))
    printf "AVISO\t%s\t%s\tLa imagen se creó, pero algún metadato no pudo escribirse\n" \
      "$(safe_log_value "$SOURCE_FILE")" "$(safe_log_value "$OUTPUT_FILE")" >> "$LOG_FILE"
  elif [[ -n "$FACE_WARNING" ]]; then
    printf "AVISO\t%s\t%s\t%s\n" \
      "$(safe_log_value "$SOURCE_FILE")" "$(safe_log_value "$OUTPUT_FILE")" "$FACE_WARNING" >> "$LOG_FILE"
  else
    printf "OK\t%s\t%s\tGPS privado eliminado; caras modificadas: %s\n" \
      "$(safe_log_value "$SOURCE_FILE")" "$(safe_log_value "$OUTPUT_FILE")" "$FACE_COUNT" >> "$LOG_FILE"
  fi

  PROCESSED=$((PROCESSED + 1))
done < <(/usr/bin/find "$SOURCE" -type f -print0)

SUMMARY="Procesadas: $PROCESSED
Errores: $FAILED
Avisos de metadatos: $WARNINGS

Resultado: $OUTPUT_DIR"

printf "\n%s\n" "$SUMMARY"

if [[ "$MODE" == "Preparar PNG para Glaze" ]]; then
  show_info "$SUMMARY

Estas copias PNG están listas para abrirse en Glaze. Cuando Glaze termine, vuelve a ejecutar este programa y elige «Finalizar imágenes después de Glaze»."
else
  show_info "$SUMMARY

Recuerda: ninguna protección técnica garantiza que una IA no pueda utilizar una imagen. Estas copias reducen datos privados y dificultan la reutilización."
fi

/usr/bin/open "$OUTPUT_DIR"
pause_terminal
exit 0
