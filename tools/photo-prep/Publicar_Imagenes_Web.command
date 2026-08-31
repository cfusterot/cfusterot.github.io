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

VISUAL_SOURCE="$ROOT/img_originales/visual_archive"
VISUAL_OUTPUT="$ROOT/img/visual_archive"

SOURCE_SOURCE_PRIMARY="$ROOT/img_originales/source"
SOURCE_SOURCE_LEGACY="$ROOT/img_originales/visual_archive/source"
SOURCE_OUTPUT="$ROOT/img/source"

DIARY_SOURCE="$ROOT/img_originales/diary"
DIARY_OUTPUT="$ROOT/img/diary"

echo "Web images: max 1600px long edge / JPEG quality 80"
echo "Web video:  max 1280px wide / H.264 CRF 26"
echo "Repositorio: $ROOT"
echo "Visual Archive origen:  $VISUAL_SOURCE"
echo "Visual Archive destino: $VISUAL_OUTPUT"
echo "Source destino:         $SOURCE_OUTPUT"
echo "Diary origen:           $DIARY_SOURCE"
echo "Diary destino:          $DIARY_OUTPUT"
echo

if [[ ! -d "$VISUAL_SOURCE" ]]; then
    echo "ERROR: no existe: $VISUAL_SOURCE"
    exit 1
fi

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
for candidate in "$SOURCE_SOURCE_PRIMARY" "$SOURCE_SOURCE_LEGACY"; do
    if [[ -d "$candidate" && -n "$(find "$candidate" -type f -iname '*.pdf' -print -quit 2>/dev/null)" ]]; then
        HAS_SOURCE_PDF=true
        break
    fi
done

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

PYTHON="$(command -v python3 || true)"
MAGICK="$(command -v magick || true)"
FFMPEG="$(command -v ffmpeg || true)"
PDFTOPPM="$(command -v pdftoppm || true)"

[[ -n "$PYTHON" ]] || { echo "ERROR: python3 no está disponible."; exit 1; }
[[ -n "$MAGICK" ]] || { echo "ERROR: ImageMagick no está disponible."; exit 1; }
[[ -n "$FFMPEG" ]] || { echo "ERROR: FFmpeg no está disponible."; exit 1; }

export VISUAL_SOURCE VISUAL_OUTPUT SOURCE_SOURCE_PRIMARY SOURCE_SOURCE_LEGACY SOURCE_OUTPUT DIARY_SOURCE DIARY_OUTPUT MAGICK FFMPEG PDFTOPPM

"$PYTHON" <<'PY'
from pathlib import Path
import os
import shutil
import subprocess
import sys
from urllib.parse import quote

visual_source = Path(os.environ["VISUAL_SOURCE"]).resolve()
visual_output = Path(os.environ["VISUAL_OUTPUT"]).resolve()

source_primary = Path(os.environ["SOURCE_SOURCE_PRIMARY"]).resolve()
source_legacy = Path(os.environ["SOURCE_SOURCE_LEGACY"]).resolve()
source_output = Path(os.environ["SOURCE_OUTPUT"]).resolve()

diary_source = Path(os.environ["DIARY_SOURCE"]).resolve()
diary_output = Path(os.environ["DIARY_OUTPUT"]).resolve()

magick = os.environ["MAGICK"]
ffmpeg = os.environ["FFMPEG"]
pdftoppm = os.environ.get("PDFTOPPM", "")

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".heic", ".heif", ".webp"}
VIDEO_EXTS = {".mp4", ".mov", ".m4v"}

processed = 0
errors = 0

print("Comprobando estructura…")

def process_tree(source: Path, output: Path, *, skip_top_level=None):
    global processed, errors

    if not source.exists():
        return

    skip_top_level = set(skip_top_level or [])

    output.mkdir(parents=True, exist_ok=True)

    # Mirror directories, but skip any redirected top-level directory.
    for directory in sorted(p for p in source.rglob("*") if p.is_dir()):
        rel = directory.relative_to(source)
        if rel.parts and rel.parts[0] in skip_top_level:
            continue
        (output / rel).mkdir(parents=True, exist_ok=True)

    def run(cmd):
        subprocess.run(cmd, check=True)

    for src in sorted(p for p in source.rglob("*") if p.is_file()):
        rel = src.relative_to(source)

        # Example: visual_archive/source/... belongs to img/source/, not img/visual_archive/.
        if rel.parts and rel.parts[0] in skip_top_level:
            continue

        ext = src.suffix.lower()
        if ext not in IMAGE_EXTS | VIDEO_EXTS:
            continue

        dest_dir = output / rel.parent
        dest_dir.mkdir(parents=True, exist_ok=True)

        try:
            if ext in {".jpg", ".jpeg"}:
                dest = dest_dir / src.name
                print(f"FOTO   {rel}")
                run([
                    magick, str(src),
                    "-auto-orient",
                    "-resize", "1600x1600>",
                    "-colorspace", "sRGB",
                    "-strip",
                    "-sampling-factor", "4:2:0",
                    "-interlace", "Plane",
                    "-quality", "80",
                    str(dest),
                ])

            elif ext == ".png":
                dest = dest_dir / src.name
                print(f"PNG    {rel}")
                run([
                    magick, str(src),
                    "-auto-orient",
                    "-resize", "1600x1600>",
                    "-colorspace", "sRGB",
                    "-alpha", "on",
                    "-strip",
                    "-define", "png:compression-level=8",
                    str(dest),
                ])

            elif ext in {".tif", ".tiff", ".heic", ".heif", ".webp"}:
                dest = dest_dir / f"{src.stem}.jpg"
                print(f"FOTO   {rel}")
                run([
                    magick, str(src),
                    "-auto-orient",
                    "-resize", "1600x1600>",
                    "-colorspace", "sRGB",
                    "-background", "white",
                    "-alpha", "remove",
                    "-strip",
                    "-interlace", "Plane",
                    "-quality", "80",
                    str(dest),
                ])

            elif ext in VIDEO_EXTS:
                dest = dest_dir / f"{src.stem}.mp4"
                print(f"VIDEO  {rel}")
                print(f"       input : {src}")
                print(f"       output: {dest}")
                run([
                    ffmpeg,
                    "-hide_banner",
                    "-y",
                    "-i", str(src),
                    "-map", "0:v:0",
                    "-map", "0:a:0?",
                    "-map_metadata", "-1",
                    "-vf", "scale='if(gt(iw,1280),1280,iw)':-2,format=yuv420p",
                    "-c:v", "libx264",
                    "-preset", "veryfast",
                    "-crf", "26",
                    "-c:a", "aac",
                    "-b:a", "128k",
                    "-movflags", "+faststart",
                    str(dest),
                ])

            processed += 1

        except subprocess.CalledProcessError as exc:
            errors += 1
            print(f"ERROR procesando: {src}", file=sys.stderr)
            print(f"Comando terminó con código {exc.returncode}", file=sys.stderr)
            try:
                if dest.exists():
                    dest.unlink()
            except Exception:
                pass


def publish_source_pdfs(source: Path):
    """Copy each PDF intact and render its first page as a web preview."""
    global processed, errors

    if not source.exists():
        return

    for src in sorted(p for p in source.rglob("*") if p.is_file() and p.suffix.lower() == ".pdf"):
        rel = src.relative_to(source)
        dest = source_output / rel
        # GitHub Pages/Jekyll omits directories whose name starts with `_`.
        preview_dir = source_output / rel.parent / "pdf_previews"
        preview = preview_dir / f"{src.stem}.jpg"

        try:
            if not pdftoppm:
                raise RuntimeError("pdftoppm no está disponible")

            dest.parent.mkdir(parents=True, exist_ok=True)
            preview_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
            print(f"PDF    {rel}")
            subprocess.run([
                pdftoppm,
                "-f", "1",
                "-l", "1",
                "-singlefile",
                "-scale-to", "1200",
                "-jpeg",
                "-jpegopt", "quality=85",
                str(src),
                str(preview.with_suffix("")),
            ], check=True)
            if not preview.exists():
                raise RuntimeError(f"no se generó la portada: {preview}")
            processed += 1
        except Exception as exc:
            errors += 1
            print(f"ERROR procesando PDF: {src}", file=sys.stderr)
            print(str(exc), file=sys.stderr)


# Clean legacy mistakes from older versions.
for bad in [visual_output / "per8", visual_output / "source"]:
    if bad.exists():
        print(f"Limpiando salida antigua incorrecta: {bad}")
        shutil.rmtree(bad)

# 1) Visual Archive: everything except a mistakenly nested "source/" directory.
print()
print("=== VISUAL ARCHIVE ===")
process_tree(visual_source, visual_output, skip_top_level={"source"})

# 2) Source: preferred location is img_originales/source/.
#    For backwards compatibility, if it is still inside visual_archive/source/,
#    process it to img/source/ instead of img/visual_archive/source/.
source_inputs = []
if source_primary.exists():
    source_inputs.append(("principal", source_primary))
if source_legacy.exists():
    source_inputs.append(("legacy", source_legacy))

if source_inputs:
    print()
    print("=== SOURCE ===")
    source_output.mkdir(parents=True, exist_ok=True)

    for label, source_root in source_inputs:
        print(f"Source ({label}): {source_root}")
        process_tree(source_root, source_output)
        publish_source_pdfs(source_root)
else:
    print()
    print("SOURCE: no se encontró img_originales/source/ ni visual_archive/source/; se omite.")

# 3) Diary: simple mirrored processing.
#    Files in img_originales/diary/ are published to img/diary/.
if diary_source.exists():
    print()
    print("=== DIARY ===")
    print(f"Diary: {diary_source}")
    process_tree(diary_source, diary_output)
else:
    print()
    print("DIARY: no se encontró img_originales/diary/; se omite.")

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
    "/* Auto-generated by Publicar_Imagenes_Web.command. Do not edit by hand. */\n"
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
    "/* Auto-generated by Publicar_Imagenes_Web.command. Do not edit by hand. */\n"
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
print(f"Listo. Procesados: {processed} | Errores: {errors}")
print(f"Visual Archive: {visual_output}")
print(f"Source:         {source_output}")
print(f"Diary:          {diary_output}")
print()
print("Carpetas de salida:")
for d in sorted(p for p in visual_output.iterdir() if p.is_dir()):
    print(" -", d.name + "/")

sys.exit(1 if errors else 0)
PY
