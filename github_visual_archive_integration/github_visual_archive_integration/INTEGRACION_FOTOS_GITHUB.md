# Integración del preparador de imágenes con el portfolio

## Estructura recomendada

Copia estos archivos a tu repositorio:

```text
cfusterot.github.io/
├── visual_archive.html
├── img/
├── img_originales/               # solo local, NO Git
└── tools/
    └── photo-prep/
        ├── Publicar_Imagenes_Web.command
        ├── Preparar_Fotos_Internet.command
        ├── proteger_caras.py
        └── LEEME_original.md
```

Añade el contenido de `.gitignore_fragment` al `.gitignore` de tu repositorio.

## Cómo usarlo para la web

1. Guarda tus originales dentro de `img_originales/`.
2. Conserva dentro de `img_originales/` la misma estructura de subcarpetas que quieres tener dentro de `img/`.
3. Haz doble clic en `tools/photo-prep/Publicar_Imagenes_Web.command`.
4. Elige resolución y, si quieres, pixelado/difuminado de caras.
5. El programa crea o actualiza las copias web dentro de `img/`.
6. Solo `img/` se añade al commit de GitHub. `img_originales/` queda ignorada.

Ejemplo:

```text
img_originales/photography/natur/R1-05002-034A.jpg
                 ↓
img/photography/natur/R1-05002-034A.jpg
```

Así los `src="img/photography/..."` de `visual_archive.html` no necesitan cambiar.

## Formatos

- JPG/JPEG conserva nombre y extensión.
- PNG conserva PNG y transparencia. Esto permite usar posteriormente siluetas o recortes con fondo transparente.
- WebP conserva WebP.
- TIFF/HEIC/HEIF se convierten a JPG; el script avisa porque en esos casos el `src` del HTML debe usar `.jpg`.

## Qué protección mantiene

La versión para GitHub conserva la parte útil del programa original para publicación:

- reducción del lado largo;
- conversión a sRGB;
- compresión web;
- eliminación de metadatos privados;
- conservación de fecha cuando existe;
- autoría/copyright y términos XMP/IPTC de no entrenamiento;
- pixelado o difuminado local opcional de caras;
- mantenimiento de subcarpetas.

La declaración de no-entrenamiento en metadatos expresa tus condiciones de uso, pero no constituye una barrera técnica contra un scraper que decida ignorarla. Tampoco existe una perturbación invisible que garantice bloquear todos los modelos actuales y futuros.

## Programa original

`Preparar_Fotos_Internet.command` se conserva también dentro de `tools/photo-prep/` porque incluye tus modos generales, incluida la preparación/finalización de imágenes para Glaze. `Publicar_Imagenes_Web.command` es simplemente el flujo específico del portfolio/GitHub.
