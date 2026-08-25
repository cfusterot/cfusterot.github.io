# Preparador de Fotos para Internet — Mac M1 / macOS Tahoe

Versión 1.1. Este programa crea copias de fotografías para publicar en una web, portfolio o red social. **Nunca modifica ni borra los originales.**

## Qué hace

- Reduce las imágenes a 1600, 2000 o 2500 píxeles en el lado más largo.
- Convierte las copias web a JPEG con calidad 85 y perfil sRGB.
- Ofrece una marca de agua discreta, una marca central más visible o ninguna marca.
- Elimina GPS, número de serie de cámara, miniaturas y otros metadatos privados.
- Conserva únicamente la fecha de captura cuando está disponible.
- Añade autoría, copyright y una declaración IPTC/XMP que prohíbe el entrenamiento de IA y la minería de datos.
- Mantiene las subcarpetas del origen.
- Registra cada imagen procesada y continúa aunque una imagen concreta esté dañada.
- Admite como entrada `.tif`, `.tiff`, `.png`, `.jpg`, `.jpeg`, `.heic`, `.heif` y `.webp`, también con extensiones en mayúsculas.
- Puede detectar y pixelar o difuminar caras localmente; el registro indica cuántas encontró en cada fotografía.

La declaración «No autorizado para entrenamiento» es una indicación de derechos legible por máquinas, pero no obliga técnicamente a un recopilador que decida ignorarla. Algunas webs también eliminan los metadatos al subir imágenes. Por eso la marca visible y la reducción de resolución son capas importantes.

## Protección de caras

En cada ejecución puedes elegir:

- **Sin modificar caras**.
- **Pixelar caras**, la opción visualmente más fuerte.
- **Difuminar caras**, con un resultado más suave.

La detección utiliza OpenCV completamente en el Mac. No envía las caras ni las fotografías a Internet. En la primera ejecución con esta opción se descarga el componente de OpenCV compatible con Apple Silicon.

La detección automática no es infalible: puede omitir perfiles, caras pequeñas, parcialmente tapadas o con poca luz, y ocasionalmente marcar como cara un objeto. Revisa las copias antes de publicarlas, especialmente cuando el registro indique `caras modificadas: 0` y sepas que había personas.

Esta función no se presenta como Fawkes. El paquete público actual de Fawkes utiliza dependencias antiguas que no están mantenidas para macOS Tahoe en Apple Silicon. Pixelar o difuminar es visible, pero ofrece un resultado más verificable que fingir una alteración invisible incompatible.

## Tres modos

### 1. Crear copias web protegidas

Produce directamente JPEG preparados para publicar en `Fotos_para_Internet`.

### 2. Preparar PNG para Glaze

Produce PNG en `PNG_para_Glaze`. Glaze recomienda trabajar con PNG para calcular sus perturbaciones protectoras.

Después:

1. Descarga Glaze únicamente desde [el proyecto de la Universidad de Chicago](https://glaze.cs.uchicago.edu/downloads.html).
2. Para un Mac M1 utiliza **Glaze 2.1, macOS — Apple CPUs**.
3. Procesa con Glaze la carpeta `PNG_para_Glaze`.
4. Abre de nuevo este programa y elige el tercer modo.

### 3. Finalizar imágenes después de Glaze

Selecciona como origen la carpeta de resultados creada por Glaze. El programa la convierte a JPEG web, añade la marca de agua elegida y vuelve a incorporar los metadatos de derechos.

## Instalación y uso

1. Descomprime el ZIP.
2. Haz clic derecho sobre `Preparar_Fotos_Internet.command` y elige **Abrir**.
3. Si macOS dice que no puede verificar al desarrollador, vuelve a pulsar **Abrir** desde el menú contextual.
4. Selecciona el modo, la carpeta de origen y el destino.

El programa necesita Homebrew. La primera vez instala automáticamente ImageMagick y ExifTool si no están presentes. Descarga Homebrew solamente desde [brew.sh](https://brew.sh).

Si utilizas un disco externo, macOS puede pedir acceso para Terminal. Concédelo en **Ajustes del Sistema > Privacidad y seguridad > Archivos y carpetas > Terminal > Volúmenes extraíbles**.

## Qué no puede garantizar

No existe una modificación invisible que vuelva una fotografía inutilizable para todas las IA presentes y futuras. Glaze está pensado principalmente para dificultar la imitación del estilo artístico y puede ser menos eficaz con determinadas fotografías. Las perturbaciones también pueden debilitarse al redimensionar o procesar nuevamente la imagen.

La estrategia más prudente es conservar el original sin modificar, publicar solamente una copia reducida, usar una marca visible cuando sea apropiado y revisar las opciones de exclusión de entrenamiento de la plataforma donde se publica.

## Privacidad

El programa se ejecuta completamente en tu Mac. No sube imágenes, no necesita una cuenta y no envía fotografías a ningún servidor. Solo Homebrew accede a Internet para instalar los dos componentes técnicos necesarios.
