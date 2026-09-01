#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

find_repo_root() {
    local dir="$SCRIPT_DIR"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/index.html" && -d "$dir/img_originales" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

ROOT="$(find_repo_root || true)"

if [[ -z "$ROOT" ]]; then
    echo "ERROR: no encuentro la raíz del repositorio."
    echo "Busqué desde: $SCRIPT_DIR"
    echo "La raíz debe contener index.html e img_originales/."
    exit 1
fi

cd "$ROOT" || exit 1

SOURCE_ROOT="$ROOT/img_originales"
OUTPUT_ROOT="$ROOT/img"
SUPPORT_DIR="$HOME/Library/Application Support/PublicadorImagenesWeb"
FACE_VENV="$SUPPORT_DIR/venv-caras"
RUN_DATE="$(date '+%Y-%m-%d_%H-%M-%S')"
LOG_FILE="$SUPPORT_DIR/Publicacion_\${RUN_DATE}.tsv"
mkdir -p "$SUPPORT_DIR"

choose_from_list() {
    local title="$1"
    local prompt="$2"
    local default_value="$3"
    shift 3
    /usr/bin/osascript - "$title" "$prompt" "$default_value" "$@" <<'APPLESCRIPT'
on run argv
    set dialogTitle to item 1 of argv
    set dialogPrompt to item 2 of argv
    set defaultValue to item 3 of argv
    set optionsList to items 4 thru -1 of argv
    set chosenItem to choose from list optionsList with title dialogTitle with prompt dialogPrompt default items {defaultValue} OK button name "Continuar" cancel button name "Cancelar"
    if chosenItem is false then return ""
    return item 1 of chosenItem
end run
APPLESCRIPT
}

ask_text() {
    local prompt="$1"
    /usr/bin/osascript - "$prompt" <<'APPLESCRIPT'
on run argv
    try
        set answerDialog to display dialog (item 1 of argv) default answer "" with title "Preparar y publicar imágenes" buttons {"Continuar"} default button "Continuar"
        return text returned of answerDialog
    on error number -128
        return ""
    end try
end run
APPLESCRIPT
}

PROFILE_CHOICE="$(choose_from_list \
    "Preparar y publicar imágenes" \
    "Elige el equilibrio entre calidad y peso" \
    "Equilibrado — recomendado" \
    "Ligero — conexiones lentas" \
    "Equilibrado — recomendado" \
    "Alta calidad — más detalle")"

case "$PROFILE_CHOICE" in
    "Ligero — conexiones lentas")
        MAX_SIZE=1200; JPEG_QUALITY=74; VIDEO_WIDTH=1080; VIDEO_CRF=29; PDF_SIZE=1000 ;;
    "Equilibrado — recomendado")
        MAX_SIZE=1400; JPEG_QUALITY=78; VIDEO_WIDTH=1280; VIDEO_CRF=27; PDF_SIZE=1200 ;;
    "Alta calidad — más detalle")
        MAX_SIZE=1800; JPEG_QUALITY=82; VIDEO_WIDTH=1600; VIDEO_CRF=25; PDF_SIZE=1400 ;;
    *)
        echo "Operación cancelada."; exit 0 ;;
esac

FACE_CHOICE="$(choose_from_list \
    "Preparar y publicar imágenes" \
    "Tratamiento facial (revisa siempre el resultado)" \
    "Sin modificar caras" \
    "Sin modificar caras" \
    "Textura sutil — experimental, sin garantía" \
    "Difuminar caras — anonimización visible" \
    "Pixelar caras — anonimización fuerte")"

case "$FACE_CHOICE" in
    "Sin modificar caras") FACE_MODE="none" ;;
    "Textura sutil — experimental, sin garantía") FACE_MODE="subtle" ;;
    "Difuminar caras — anonimización visible") FACE_MODE="blur" ;;
    "Pixelar caras — anonimización fuerte") FACE_MODE="pixelate" ;;
    *) echo "Operación cancelada."; exit 0 ;;
esac

REBUILD_CHOICE="$(choose_from_list \
    "Preparar y publicar imágenes" \
    "¿Quieres reconstruir todas las copias o solo actualizar cambios?" \
    "Regenerar todo — recomendado ahora" \
    "Regenerar todo — recomendado ahora" \
    "Actualizar solo archivos nuevos o modificados")"

case "$REBUILD_CHOICE" in
    "Regenerar todo — recomendado ahora") FORCE_REBUILD=1 ;;
    "Actualizar solo archivos nuevos o modificados") FORCE_REBUILD=0 ;;
    *) echo "Operación cancelada."; exit 0 ;;
esac

AUTHOR="$(ask_text "Nombre de autora/copyright (opcional)")"

echo
echo "Preparar y publicar imágenes"
echo "========================================"
echo "Origen:  $SOURCE_ROOT"
echo "Destino: $OUTPUT_ROOT"
echo "Perfil:  $PROFILE_CHOICE"
echo "Caras:   $FACE_CHOICE"
echo "Modo:    $REBUILD_CHOICE"
echo "Los originales no se modifican y no se borra ningún archivo de img/."
echo

BREW="$(command -v brew || true)"

if ! command -v magick >/dev/null 2>&1; then
    if [[ -n "$BREW" ]]; then
        echo "ImageMagick no encontrado; instalando con Homebrew…"
        "$BREW" install imagemagick
    else
        echo "ERROR: ImageMagick (magick) no está instalado y Homebrew no está disponible."
        exit 1
    fi
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    if [[ -n "$BREW" ]]; then
        echo "FFmpeg no encontrado; instalando con Homebrew…"
        "$BREW" install ffmpeg
    else
        echo "ERROR: FFmpeg no está instalado y Homebrew no está disponible."
        exit 1
    fi
fi

HAS_SOURCE_PDF=false
if [[ -n "$(find "$SOURCE_ROOT" -type f -iname '*.pdf' -print -quit 2>/dev/null)" ]]; then
    HAS_SOURCE_PDF=true
fi

if $HAS_SOURCE_PDF && ! command -v pdftoppm >/dev/null 2>&1; then
    if [[ -n "$BREW" ]]; then
        echo "Poppler no encontrado; instalando para generar portadas de PDF…"
        "$BREW" install poppler
    else
        echo "ERROR: se encontraron PDFs pero falta Poppler (pdftoppm)."
        echo "Instálalo con: brew install poppler"
        exit 1
    fi
fi

if ! command -v exiftool >/dev/null 2>&1; then
    if [[ -n "$BREW" ]]; then
        echo "ExifTool no encontrado; instalando para limpiar GPS y escribir derechos…"
        "$BREW" install exiftool
    else
        echo "ERROR: falta ExifTool y Homebrew no está disponible."
        exit 1
    fi
fi

PYTHON="$(command -v python3 || true)"
if [[ "$FACE_MODE" != "none" ]]; then
    if [[ -z "$BREW" ]]; then
        echo "ERROR: el tratamiento facial necesita Homebrew para preparar Python y OpenCV."
        exit 1
    fi
    PYTHON_PREFIX="$("$BREW" --prefix python@3.13 2>/dev/null || true)"
    PYTHON313="$PYTHON_PREFIX/bin/python3.13"
    if [[ ! -x "$PYTHON313" ]]; then
        echo "Instalando Python 3.13 para el detector facial…"
        "$BREW" install python@3.13
        PYTHON_PREFIX="$("$BREW" --prefix python@3.13)"
        PYTHON313="$PYTHON_PREFIX/bin/python3.13"
    fi
    if [[ ! -x "$FACE_VENV/bin/python" ]]; then
        echo "Preparando el detector facial local (solo la primera vez)…"
        "$PYTHON313" -m venv "$FACE_VENV"
    fi
    if ! "$FACE_VENV/bin/python" -c 'import cv2' >/dev/null 2>&1; then
        "$FACE_VENV/bin/python" -m pip install --disable-pip-version-check --only-binary=:all: \
            "opencv-python-headless==4.12.0.88"
    fi
    PYTHON="$FACE_VENV/bin/python"
fi

MAGICK="$(command -v magick || true)"
FFMPEG="$(command -v ffmpeg || true)"
PDFTOPPM="$(command -v pdftoppm || true)"
EXIFTOOL="$(command -v exiftool || true)"

[[ -n "$PYTHON" ]] || { echo "ERROR: python3 no está disponible."; exit 1; }
[[ -n "$MAGICK" ]] || { echo "ERROR: ImageMagick no está disponible."; exit 1; }
[[ -n "$FFMPEG" ]] || { echo "ERROR: FFmpeg no está disponible."; exit 1; }
[[ -n "$EXIFTOOL" ]] || { echo "ERROR: ExifTool no está disponible."; exit 1; }

export SOURCE_ROOT OUTPUT_ROOT MAGICK FFMPEG PDFTOPPM EXIFTOOL
export MAX_SIZE JPEG_QUALITY VIDEO_WIDTH VIDEO_CRF PDF_SIZE FACE_MODE AUTHOR LOG_FILE FORCE_REBUILD

set +e
"$PYTHON" <<'PY'
from __future__ import annotations

from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
from urllib.parse import quote

source_root = Path(os.environ["SOURCE_ROOT"]).resolve()
output_root = Path(os.environ["OUTPUT_ROOT"]).resolve()
visual_output = output_root / "visual_archive"
source_output = output_root / "source"

magick = os.environ["MAGICK"]
ffmpeg = os.environ["FFMPEG"]
pdftoppm = os.environ.get("PDFTOPPM", "")
exiftool = os.environ["EXIFTOOL"]
max_size = int(os.environ["MAX_SIZE"])
jpeg_quality = int(os.environ["JPEG_QUALITY"])
video_width = int(os.environ["VIDEO_WIDTH"])
video_crf = int(os.environ["VIDEO_CRF"])
pdf_size = int(os.environ["PDF_SIZE"])
face_mode = os.environ["FACE_MODE"]
force_rebuild = os.environ.get("FORCE_REBUILD", "0") == "1"
author = os.environ.get("AUTHOR", "").strip()
log_file = Path(os.environ["LOG_FILE"])

if face_mode != "none":
    import cv2
    import numpy as np

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".heic", ".heif", ".webp"}
VIDEO_EXTS = {".mp4", ".mov", ".m4v"}
COPY_EXTS = {".gif", ".svg"}

processed = 0
errors = 0
skipped = 0

settings_file = output_root / ".publicador_web_settings.json"
settings = {
    "version": 3,
    "max_size": max_size,
    "jpeg_quality": jpeg_quality,
    "video_width": video_width,
    "video_crf": video_crf,
    "face_mode": face_mode,
    "author": author,
}
try:
    same_settings = json.loads(settings_file.read_text(encoding="utf-8")) == settings
except (OSError, ValueError):
    same_settings = False
if force_rebuild:
    same_settings = False

print("Comprobando estructura completa de img_originales…")
supported_exts = IMAGE_EXTS | VIDEO_EXTS | COPY_EXTS | {".pdf"}
top_folders = sorted(p for p in source_root.iterdir() if p.is_dir() and not p.name.startswith("."))
if not top_folders:
    raise SystemExit(f"No se encontraron carpetas dentro de {source_root}")

total_detected = 0
pdf_detected = 0
print("Carpetas detectadas:")
for folder in top_folders:
    items = [
        p for p in folder.rglob("*")
        if p.is_file() and p.suffix.lower() in supported_exts
    ]
    folder_pdfs = sum(p.suffix.lower() == ".pdf" for p in items)
    total_detected += len(items)
    pdf_detected += folder_pdfs
    pdf_note = f" · PDF: {folder_pdfs}" if folder_pdfs else ""
    print(f"  - {folder.name}/: {len(items)} elementos{pdf_note}")
print(f"Total detectado: {total_detected} elementos · PDF originales: {pdf_detected}")

def clean_work_files():
    if not output_root.exists():
        return
    for temporary in output_root.rglob(".*.webwork-*.png"):
        try:
            temporary.unlink()
        except OSError:
            pass

clean_work_files()

def expanded_box(x: int, y: int, w: int, h: int, width: int, height: int):
    """Incluye frente, mandibula y laterales, no solo el centro de la cara."""
    margin_x = int(w * 0.20)
    margin_top = int(h * 0.24)
    margin_bottom = int(h * 0.30)
    return (
        max(0, x - margin_x),
        max(0, y - margin_top),
        min(width, x + w + margin_x),
        min(height, y + h + margin_bottom),
    )


def intersection_over_union(a, b) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    intersection = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    if not intersection:
        return 0.0
    area_a = (ax2 - ax1) * (ay2 - ay1)
    area_b = (bx2 - bx1) * (by2 - by1)
    return intersection / float(area_a + area_b - intersection)


def deduplicate(boxes, threshold: float = 0.32):
    """Fusiona detecciones repetidas de los clasificadores frontal/perfil."""
    boxes = sorted(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), reverse=True)
    kept = []
    for box in boxes:
        if all(intersection_over_union(box, previous) < threshold for previous in kept):
            kept.append(box)
    return kept


def detect_faces(image: np.ndarray):
    if image.ndim == 2:
        bgr = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    elif image.shape[2] == 4:
        bgr = image[:, :, :3]
    else:
        bgr = image

    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.createCLAHE(clipLimit=1.8, tileGridSize=(8, 8)).apply(gray)
    height, width = gray.shape[:2]
    min_side = max(38, int(min(width, height) * 0.028))
    min_profile_side = max(54, int(min(width, height) * 0.045))

    cascade_dir = Path(cv2.data.haarcascades)
    frontal = cv2.CascadeClassifier(str(cascade_dir / "haarcascade_frontalface_default.xml"))
    profile = cv2.CascadeClassifier(str(cascade_dir / "haarcascade_profileface.xml"))
    if frontal.empty() or profile.empty():
        raise RuntimeError("No se pudieron cargar los detectores faciales locales")

    raw_boxes = []
    for x, y, w, h in frontal.detectMultiScale(
        gray, scaleFactor=1.08, minNeighbors=6,
        minSize=(min_side, min_side), flags=cv2.CASCADE_SCALE_IMAGE,
    ):
        raw_boxes.append((int(x), int(y), int(x + w), int(y + h)))

    # El clasificador de perfil incluido con OpenCV reconoce una orientacion.
    # Repetimos sobre la imagen reflejada para cubrir ambos lados.
    # Los Haar de perfil producen mas falsos positivos en collages y reflejos.
    # Se usan como respaldo solo cuando el detector frontal no encontro nada.
    for mirrored in ((False, True) if not raw_boxes else ()):
        view = cv2.flip(gray, 1) if mirrored else gray
        for x, y, w, h in profile.detectMultiScale(
            view, scaleFactor=1.09, minNeighbors=7,
            minSize=(min_profile_side, min_profile_side),
            flags=cv2.CASCADE_SCALE_IMAGE,
        ):
            x = width - x - w if mirrored else x
            raw_boxes.append((int(x), int(y), int(x + w), int(y + h)))

    return deduplicate(raw_boxes)


def soft_mask(height: int, width: int, feather: float = 0.10) -> np.ndarray:
    mask = np.zeros((height, width), dtype=np.float32)
    cv2.ellipse(
        mask, (width // 2, height // 2),
        (max(1, int(width * 0.49)), max(1, int(height * 0.49))),
        0, 0, 360, 1.0, -1, cv2.LINE_AA,
    )
    sigma = max(2.0, min(height, width) * feather)
    mask = cv2.GaussianBlur(mask, (0, 0), sigma)
    maximum = float(mask.max())
    return mask / maximum if maximum else mask


def pixelate(region: np.ndarray) -> np.ndarray:
    height, width = region.shape[:2]
    tiny = cv2.resize(
        region, (max(5, width // 22), max(5, height // 22)),
        interpolation=cv2.INTER_AREA,
    )
    return cv2.resize(tiny, (width, height), interpolation=cv2.INTER_NEAREST)


def blur(region: np.ndarray) -> np.ndarray:
    sigma = max(10.0, min(region.shape[:2]) * 0.18)
    return cv2.GaussianBlur(region, (0, 0), sigmaX=sigma, sigmaY=sigma)


def subtle_perturbation(region: np.ndarray, seed: int) -> np.ndarray:
    """Cambia discretamente luminancia y crominancia a varias escalas.

    No equivale a Fawkes/LowKey y no se presenta como garantia frente a un
    modelo adaptativo, redimensionado o preprocesado posterior.
    """
    rng = np.random.default_rng(seed)
    height, width = region.shape[:2]
    lab = cv2.cvtColor(region, cv2.COLOR_BGR2LAB).astype(np.float32)
    fine = rng.normal(0.0, 1.0, (height, width)).astype(np.float32)
    coarse = cv2.GaussianBlur(fine, (0, 0), max(1.2, min(height, width) / 55.0))
    coarse /= max(float(coarse.std()), 1e-6)
    yy, xx = np.mgrid[0:height, 0:width]
    wave = np.sin(
        (xx + yy * 0.73) * (np.pi / 3.7) + rng.uniform(0, np.pi * 2)
    ).astype(np.float32)
    lab[:, :, 0] += coarse * 1.7 + wave * 0.8
    lab[:, :, 1] += fine * 2.2 + wave * 1.4
    lab[:, :, 2] -= fine * 2.0 - wave * 1.2
    return cv2.cvtColor(np.clip(lab, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)


def blend(original: np.ndarray, treated: np.ndarray, mask: np.ndarray) -> np.ndarray:
    alpha = mask if original.ndim == 2 else mask[:, :, None]
    result = original.astype(np.float32) * (1.0 - alpha) + treated.astype(np.float32) * alpha
    return np.clip(result, 0, 255).astype(np.uint8)

def protect_faces(image_path: Path, mode: str) -> int:
    image = cv2.imread(str(image_path), cv2.IMREAD_UNCHANGED)
    if image is None:
        raise RuntimeError(f"No se pudo leer la imagen temporal: {image_path}")

    faces = detect_faces(image)
    image_height, image_width = image.shape[:2]
    base_seed = int.from_bytes(
        hashlib.sha256(image_path.name.encode("utf-8")).digest()[:8], "big"
    )

    for index, (x1, y1, x2, y2) in enumerate(faces):
        x1, y1, x2, y2 = expanded_box(
            x1, y1, x2 - x1, y2 - y1, image_width, image_height
        )
        region = image[y1:y2, x1:x2]
        if region.size == 0:
            continue
        color_region = region if region.ndim == 2 else region[:, :, :3]
        bgr_region = (
            cv2.cvtColor(color_region, cv2.COLOR_GRAY2BGR)
            if color_region.ndim == 2 else color_region
        )

        if mode == "pixelate":
            treated = pixelate(bgr_region)
            mask = soft_mask(*bgr_region.shape[:2], feather=0.045)
        elif mode == "blur":
            treated = blur(bgr_region)
            mask = soft_mask(*bgr_region.shape[:2], feather=0.075)
        else:
            treated = subtle_perturbation(bgr_region, base_seed + index)
            mask = soft_mask(*bgr_region.shape[:2], feather=0.13)

        blended = blend(bgr_region, treated, mask)
        if region.ndim == 2:
            image[y1:y2, x1:x2] = cv2.cvtColor(blended, cv2.COLOR_BGR2GRAY)
        else:
            image[y1:y2, x1:x2, :3] = blended

    if not cv2.imwrite(
        str(image_path), image, [cv2.IMWRITE_PNG_COMPRESSION, 6]
    ):
        raise RuntimeError(f"No se pudo guardar la imagen temporal: {image_path}")
    return len(faces)


def write_rights_metadata(src: Path, dest: Path):
    rights = (
        f"© {author}. Todos los derechos reservados."
        if author else "Todos los derechos reservados."
    )
    no_ai = (
        "No autorizado para entrenamiento de inteligencia artificial, "
        "aprendizaje automático, minería de datos ni contenido derivado."
    )
    cmd = [
        exiftool, "-overwrite_original", "-all=",
        "-TagsFromFile", str(src), "-DateTimeOriginal", "-CreateDate",
        f"-XMP-dc:Rights={rights}",
        "-XMP-xmpRights:Marked=True",
        f"-XMP-xmpRights:UsageTerms={no_ai}",
        f"-IPTC:CopyrightNotice={rights}",
        f"-IPTC:SpecialInstructions={no_ai}",
    ]
    if author:
        cmd.extend([
            f"-Artist={author}", f"-XMP-dc:Creator={author}",
            f"-IPTC:By-line={author}",
        ])
    cmd.append(str(dest))
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def process_tree(source: Path, output: Path):
    global processed, errors, skipped

    output.mkdir(parents=True, exist_ok=True)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    if not log_file.exists():
        log_file.write_text(
            "estado\torigen\tsalida\tcaras\tdetalle\n", encoding="utf-8"
        )

    def run(cmd):
        subprocess.run(cmd, check=True)

    for src in sorted(p for p in source.rglob("*") if p.is_file()):
        rel = src.relative_to(source)
        if any(part.startswith(".") for part in rel.parts):
            continue
        # La antigua visual_archive/source/ se redirige después a img/source/
        # para no crear dos bibliotecas ni contaminar Visual Archive.
        if rel.parts[:2] == ("visual_archive", "source"):
            continue

        ext = src.suffix.lower()
        if ext not in IMAGE_EXTS | VIDEO_EXTS | COPY_EXTS:
            continue

        dest_dir = output / rel.parent
        dest_dir.mkdir(parents=True, exist_ok=True)
        if ext in COPY_EXTS:
            dest = dest_dir / src.name
        elif ext in VIDEO_EXTS:
            dest = dest_dir / f"{src.stem}.mp4"
        else:
            dest = (
                dest_dir / src.name
                if ext in {".jpg", ".jpeg", ".png"}
                else dest_dir / f"{src.stem}.jpg"
            )

        if (
            same_settings and dest.exists()
            and dest.stat().st_mtime >= src.stat().st_mtime
        ):
            skipped += 1
            continue

        work = None
        face_count = 0

        try:
            if ext in COPY_EXTS:
                print(f"COPIA  {rel}")
                shutil.copy2(src, dest)
            elif ext in VIDEO_EXTS:
                print(f"VIDEO  {rel}")
                run([
                    ffmpeg, "-hide_banner", "-loglevel", "warning", "-y",
                    "-i", str(src),
                    "-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "-1",
                    "-vf",
                    f"scale='if(gt(iw,{video_width}),{video_width},iw)':-2,"
                    "format=yuv420p",
                    "-c:v", "libx264", "-preset", "slow",
                    "-crf", str(video_crf),
                    "-c:a", "aac", "-b:a", "128k",
                    "-movflags", "+faststart", str(dest),
                ])
            else:
                keep_png = ext == ".png"
                work = dest_dir / f".{src.stem}.webwork-{os.getpid()}.png"
                print(f"{'PNG' if keep_png else 'FOTO':5}  {rel}")

                prepare_cmd = [
                    magick, str(src), "-auto-orient",
                    "-filter", "Lanczos", "-define", "filter:blur=0.92",
                    "-resize", f"{max_size}x{max_size}>",
                    "-colorspace", "sRGB",
                ]
                if keep_png:
                    prepare_cmd.extend(["-alpha", "on"])
                else:
                    prepare_cmd.extend([
                        "-background", "white", "-alpha", "remove", "-alpha", "off"
                    ])
                prepare_cmd.extend(["-strip", str(work)])
                run(prepare_cmd)

                if face_mode != "none":
                    face_count = protect_faces(work, face_mode)

                if keep_png:
                    run([
                        magick, str(work), "-strip",
                        "-define", "png:compression-level=9", str(dest),
                    ])
                else:
                    run([
                        magick, str(work),
                        "-background", "white", "-alpha", "remove", "-alpha", "off",
                        "-strip", "-sampling-factor", "4:2:0",
                        "-interlace", "Plane",
                        "-define", "jpeg:dct-method=float",
                        "-quality", str(jpeg_quality), str(dest),
                    ])

                write_rights_metadata(src, dest)

            processed += 1
            with log_file.open("a", encoding="utf-8") as handle:
                handle.write(
                    f"OK\t{src}\t{dest}\t{face_count}\t"
                    "GPS eliminado; copia web generada\n"
                )

        except Exception as exc:
            errors += 1
            print(f"ERROR procesando {src}: {exc}", file=sys.stderr)
            with log_file.open("a", encoding="utf-8") as handle:
                handle.write(f"ERROR\t{src}\t{dest or ''}\t0\t{exc}\n")
            if dest and dest.exists():
                dest.unlink()
        finally:
            if work and work.exists():
                work.unlink()



def publish_source_pdfs(source: Path) -> int:
    """Copy every Source PDF and atomically rebuild its first-page preview."""
    global processed, errors

    if not source.exists():
        return 0

    pdf_files = sorted(
        p for p in source.rglob("*")
        if p.is_file() and p.suffix.lower() == ".pdf"
    )
    if not pdf_files:
        print("PDF Source: 0 originales; no hay ninguna portada que regenerar.")
        return 0

    regenerated = 0
    for src in pdf_files:
        rel = src.relative_to(source)
        dest = source_output / rel
        preview_dir = source_output / rel.parent / "pdf_previews"
        preview = preview_dir / f"{src.stem}.jpg"
        temp_prefix = preview_dir / f".{src.stem}.preview-{os.getpid()}"
        temp_preview = Path(str(temp_prefix) + ".jpg")

        try:
            if not pdftoppm:
                raise RuntimeError("pdftoppm no está disponible")

            dest.parent.mkdir(parents=True, exist_ok=True)
            preview_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
            if temp_preview.exists():
                temp_preview.unlink()

            print(f"PDF    {rel} → {preview.relative_to(output_root)}")
            subprocess.run([
                pdftoppm,
                "-f", "1", "-l", "1", "-singlefile",
                "-scale-to", str(pdf_size),
                "-jpeg", "-jpegopt", f"quality={jpeg_quality}",
                str(src), str(temp_prefix),
            ], check=True)

            if not temp_preview.exists() or temp_preview.stat().st_size == 0:
                raise RuntimeError(f"no se generó la portada temporal: {temp_preview}")

            # Sustitución atómica: la portada anterior desaparece únicamente
            # después de haber comprobado que la nueva existe y no está vacía.
            os.replace(temp_preview, preview)
            os.utime(preview, None)
            processed += 1
            regenerated += 1
            with log_file.open("a", encoding="utf-8") as handle:
                handle.write(
                    f"OK\t{src}\t{preview}\t0\tPortada PDF regenerada\n"
                )
        except Exception as exc:
            errors += 1
            print(f"ERROR procesando PDF {src}: {exc}", file=sys.stderr)
            with log_file.open("a", encoding="utf-8") as handle:
                handle.write(f"ERROR\t{src}\t{preview}\t0\t{exc}\n")
        finally:
            if temp_preview.exists():
                temp_preview.unlink()

    return regenerated



print()
print("=== TODO IMG_ORIGINALES → IMG ===")
process_tree(source_root, output_root)

# Source PDFs need a web preview of their first page. The normal/current
# location is img_originales/source/. The legacy nested path is only used when
# the current one does not exist.
source_primary = source_root / "source"
source_legacy = source_root / "visual_archive" / "source"
pdf_previews_regenerated = 0
if source_primary.exists():
    pdf_previews_regenerated = publish_source_pdfs(source_primary)
elif source_legacy.exists():
    print("SOURCE: usando la ruta antigua visual_archive/source/")
    process_tree(source_legacy, source_output)
    pdf_previews_regenerated = publish_source_pdfs(source_legacy)
else:
    print("SOURCE: no se encontró img_originales/source/.")

print(f"Portadas PDF regeneradas: {pdf_previews_regenerated}")

# No debe entrar ningún temporal de procesamiento en los manifiestos.
clean_work_files()


# Generate a static JS media manifest.
# GitHub Pages cannot enumerate a directory at runtime, so the browser reads this file instead.
manifest = visual_output.parent.parent / "archive_media_manifest.js"

records = []
for p in sorted(x for x in visual_output.rglob("*") if x.is_file()):
    ext = p.suffix.lower()
    if ext not in {".jpg", ".jpeg", ".png", ".mp4"}:
        continue

    rel = p.relative_to(visual_output)
    parts = rel.parts
    top = parts[0] if parts else ""

    entry = {
        "src": "img/visual_archive/" + quote(rel.as_posix(), safe="/"),
        "type": "video" if ext == ".mp4" else "img",
    }

    if top == "cutouts":
        entry["kind"] = "cutout"
        entry["project"] = "cutouts"
    elif top == "collage":
        entry["project"] = "escitalopram"
    elif top == "super8":
        entry["project"] = "video"
    elif top == "photography":
        # photography/<project>/file.ext -> project name
        entry["project"] = parts[1] if len(parts) >= 3 else "photo"
    else:
        entry["project"] = top or "archive"

    records.append(entry)

import json
manifest.write_text(
    "/* Auto-generated by Preparar_y_Publicar_Web.command. Do not edit by hand. */\n"
    "window.ARCHIVE_MEDIA = "
    + json.dumps(records, ensure_ascii=False, indent=2)
    + ";\n",
    encoding="utf-8",
)


# Generate Source media manifest separately.
# Source is deliberately NOT part of archive_media_manifest.js.
source_manifest = visual_output.parent.parent / "source_media_manifest.js"

source_records = []
if source_output.exists():
    for p in sorted(x for x in source_output.rglob("*") if x.is_file()):
        ext = p.suffix.lower()
        if ext not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
            continue

        rel = p.relative_to(source_output)
        if "_pdf_previews" in rel.parts or "pdf_previews" in rel.parts:
            continue
        source_records.append({
            # Encode each web path safely. Characters such as # and ? have a
            # special meaning in URLs and otherwise make valid files invisible.
            "src": "img/source/" + quote(rel.as_posix(), safe="/"),
            "type": "image",
            "title": p.stem.replace("_", " ").replace("-", " "),
            "description": "",
            "href": "",
        })

    for p in sorted(x for x in source_output.rglob("*.pdf") if x.is_file()):
        rel = p.relative_to(source_output)
        preview_rel = rel.parent / "pdf_previews" / f"{p.stem}.jpg"
        source_records.append({
            "src": "img/source/" + quote(preview_rel.as_posix(), safe="/"),
            "type": "pdf",
            "title": p.stem.replace("_", " ").replace("-", " "),
            "description": "",
            "href": "img/source/" + quote(rel.as_posix(), safe="/"),
        })

source_manifest.write_text(
    "/* Auto-generated by Preparar_y_Publicar_Web.command. Do not edit by hand. */\n"
    "window.SOURCE_MEDIA = "
    + json.dumps(source_records, ensure_ascii=False, indent=2)
    + ";\n",
    encoding="utf-8",
)

print()
print(f"Manifest generado: {manifest}")
print(f"Elementos Visual Archive catalogados: {len(records)}")
print(f"Source manifest generado: {source_manifest}")
print(f"Elementos Source catalogados: {len(source_records)}")
print()
if errors == 0:
    output_root.mkdir(parents=True, exist_ok=True)
    settings_file.write_text(
        json.dumps(settings, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

print(f"Listo. Procesados: {processed} | Sin cambios: {skipped} | Errores: {errors}")
print(f"Salida completa: {output_root}")
print(f"Registro:        {log_file}")
print()
print("Carpetas de salida:")
for d in sorted(p for p in output_root.iterdir() if p.is_dir()):
    print(" -", d.name + "/")

sys.exit(1 if errors else 0)
PY

STATUS=$?
set -e

if [[ $STATUS -eq 0 ]]; then
    /usr/bin/osascript - "$OUTPUT_ROOT" <<'APPLESCRIPT' >/dev/null
on run argv
    display dialog "Publicación terminada correctamente.\n\nLas copias web están en:\n" & (item 1 of argv) with title "Preparar y publicar imágenes" buttons {"Aceptar"} default button "Aceptar"
end run
APPLESCRIPT
    /usr/bin/open "$OUTPUT_ROOT"
else
    /usr/bin/osascript - "$LOG_FILE" <<'APPLESCRIPT' >/dev/null
on run argv
    display alert "La publicación terminó con errores" message "Revisa el terminal y el registro:\n" & (item 1 of argv) as critical buttons {"Aceptar"} default button "Aceptar"
end run
APPLESCRIPT
fi

exit "$STATUS"
