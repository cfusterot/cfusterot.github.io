#!/usr/bin/env python3
"""Detecta y anonimiza caras localmente. No realiza ninguna conexión de red."""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np


def expanded_box(x: int, y: int, w: int, h: int, width: int, height: int):
    margin_x = int(w * 0.14)
    margin_y = int(h * 0.18)
    x1 = max(0, x - margin_x)
    y1 = max(0, y - margin_y)
    x2 = min(width, x + w + margin_x)
    y2 = min(height, y + h + margin_y)
    return x1, y1, x2, y2


def pixelate(region: np.ndarray) -> np.ndarray:
    height, width = region.shape[:2]
    small_width = max(6, width // 18)
    small_height = max(6, height // 18)
    tiny = cv2.resize(region, (small_width, small_height), interpolation=cv2.INTER_AREA)
    return cv2.resize(tiny, (width, height), interpolation=cv2.INTER_NEAREST)


def blur(region: np.ndarray) -> np.ndarray:
    smallest_side = min(region.shape[:2])
    kernel = max(31, int(smallest_side * 0.45))
    if kernel % 2 == 0:
        kernel += 1
    return cv2.GaussianBlur(region, (kernel, kernel), 0)


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[2] not in {"pixelate", "blur"}:
        print("Uso: proteger_caras.py IMAGEN pixelate|blur", file=sys.stderr)
        return 2

    image_path = Path(sys.argv[1])
    mode = sys.argv[2]
    image = cv2.imread(str(image_path), cv2.IMREAD_UNCHANGED)
    if image is None:
        print(f"No se pudo leer: {image_path}", file=sys.stderr)
        return 3

    if image.ndim == 2:
        detection_image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    elif image.shape[2] == 4:
        detection_image = image[:, :, :3]
    else:
        detection_image = image

    gray = cv2.cvtColor(detection_image, cv2.COLOR_BGR2GRAY)
    gray = cv2.equalizeHist(gray)
    cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    detector = cv2.CascadeClassifier(cascade_path)
    if detector.empty():
        print("No se pudo cargar el detector facial local", file=sys.stderr)
        return 4

    faces = detector.detectMultiScale(
        gray,
        scaleFactor=1.08,
        minNeighbors=5,
        minSize=(38, 38),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )

    image_height, image_width = image.shape[:2]
    for x, y, w, h in faces:
        x1, y1, x2, y2 = expanded_box(x, y, w, h, image_width, image_height)
        if image.ndim == 2:
            region = image[y1:y2, x1:x2]
            image[y1:y2, x1:x2] = pixelate(region) if mode == "pixelate" else blur(region)
        else:
            color_region = image[y1:y2, x1:x2, :3]
            image[y1:y2, x1:x2, :3] = pixelate(color_region) if mode == "pixelate" else blur(color_region)

    suffix = image_path.suffix.lower()
    parameters = []
    if suffix in {".jpg", ".jpeg"}:
        parameters = [cv2.IMWRITE_JPEG_QUALITY, 88]
    elif suffix == ".png":
        parameters = [cv2.IMWRITE_PNG_COMPRESSION, 4]

    if not cv2.imwrite(str(image_path), image, parameters):
        print(f"No se pudo guardar: {image_path}", file=sys.stderr)
        return 5

    print(len(faces))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
