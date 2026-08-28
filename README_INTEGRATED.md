# /archive/ v9

## Sidebar
`science/`, `visual_archive/` and `blog/` start closed for a first-time visitor.
After that, their state is remembered in localStorage and survives navigation.
The tree is hidden for the few milliseconds while the state is restored, preventing the close/open flash.

`source` is present in the blog folder on every integrated page, including `derives.html`.

## Visual Archive switching
Inside `visual_archive.html`, clicking `escitalopram/`, `photo/` or `video/` no longer reloads the HTML page.
The URL changes with `history.pushState` and the mural is rebuilt in place.
This removes the odd page transition/flicker.

## Cutouts and automatic folder reading
A static GitHub Pages page cannot ask the server to list the contents of `img/visual_archive/cutouts/`.
Instead, `Publicar_Imagenes_Web.command` now automatically generates:

`archive_media_manifest.js`

after processing the media.

The manifest catalogs every published photograph, video and cutout.
`visual_archive.html` and the local editor load this manifest and automatically add files that are not already present in the old explicit source list.

Therefore the workflow for a new cutout is now simply:

1. Put the transparent PNG in `img_originales/visual_archive/cutouts/`.
2. Run `Publicar_Imagenes_Web.command`.
3. It creates/updates `img/visual_archive/cutouts/...`.
4. It regenerates `archive_media_manifest.js`.
5. Reload the Visual Archive/editor.

No manual HTML entry is required.

Cutouts are tagged as `data-kind="cutout"` automatically, use `object-fit: contain`, keep alpha transparency, and do not receive CSS clip shapes.


## v10 — easy summary selection
The local editor adds `[ clear wall ]` and `[ library ]`.

Workflow:
1. Open `visual_archive_editor.html`.
2. Click `[ arrange ]`.
3. Click `[ clear wall ]`.
4. Open `[ library ]`.
5. Click thumbnails to add/remove only the pieces wanted in the summary.
6. Filter the library by photo, video, cutout, or escitalopram.
7. Arrange/resize selected pieces and save/export as usual.

`[ clear wall ]` only clears the current composition. It never deletes source files or the media catalogue.


## v10.2 — library additions fixed
Items added from `[ library ]` now use the same `enableDragging()` and four-corner `enableResizing()` logic as the initial wall.
New items are also placed with the existing collision-aware packing function instead of a simple fixed cascade, preventing late additions from overlapping manually moved pieces.


## v10.3 — durable summary layout + independent catalogue views

### Saving the arrangement permanently
The local editor now downloads a real file:

`visual_archive_layout.js`

with `[ download layout ]`.

Put that file in the repository root next to `visual_archive.html`.

That file contains:
- which images are in the summary,
- position,
- size,
- z-index,
- shape,
- silhouette state,
- removed items.

This is the file to keep forever. Future HTML updates can replace `visual_archive.html` and `visual_archive_editor.html` without losing the arrangement, as long as `visual_archive_layout.js` is kept.

`[ save ]` still stores a quick working copy in localStorage.
`[ load layout ]` can restore a previously downloaded `.js` or `.json` layout file.

### Public Visual Archive
- `/visual_archive.html` uses `visual_archive_layout.js` when present.
- If no durable layout has been exported yet, it temporarily shows all media.

### Photo / Video / Escitalopram
These views are now independent of the summary layout:
- `?view=photo` always shows ALL published photography.
- `?view=video` always shows ALL published video.
- `?view=escitalopram` always shows ALL published collage/Escitalopram media.

They ignore the summary's removed list and positions, and each view is freshly packed from the top of the page.


## v10.4 — saved arrangement included
`visual_archive_layout.js` already contains the imported arrangement from the previous editor.
Do not replace this file in future HTML-only updates unless you intentionally export a newer arrangement.


## v10.5 — critical layout loader fix
The previous package had a malformed `<script src="archive_media_manifest.js">` tag in `visual_archive.html`.
Because the navigation code was nested inside that external-script element, the browser ignored that inline code and `visual_archive_layout.js` was never loaded on the public page.

This version explicitly loads:
1. `archive_media_manifest.js`
2. `visual_archive_layout.js`
3. the inline page scripts

The imported saved arrangement is already present in `visual_archive_layout.js`.


## v10.6 — robust saved-layout loading
This package now includes:
- the populated `visual_archive_layout.js`,
- a populated fallback `archive_media_manifest.js`,
- an embedded emergency copy of the saved layout inside the Visual Archive HTML.

The public page can reconstruct the curated wall from the saved layout even if the generated manifest is missing or stale.
The external `visual_archive_layout.js` remains the canonical file for future edits.


## v10.7 — editor loading fixed
The public Visual Archive was already using the durable layout, but the local editor could initialize before the manifest/layout restoration sequence completed.
The editor now explicitly:
1. syncs the media manifest,
2. builds the wall,
3. restores the saved durable layout.

If an old empty localStorage entry exists, it falls back to `visual_archive_layout.js`.
A small top-right status shows `layout: X / wall: Y` for quick verification.


## v10.8 — actual editor blank-page bug fixed
The editor had a JavaScript syntax error inside the new `[ download layout ]` handler:
a multiline string was written as a normal quoted JavaScript string.
Because that syntax error was in the editor's main script block, the whole block failed before `buildWall()` could run, which produced `layout: 43 / wall: 0`.

The string is now correctly escaped and every inline JavaScript block in `visual_archive_editor.html` has been syntax-checked with Node.


## v10.9 — complete catalogue views fixed
The previous fallback manifest accidentally represented only part of the media catalogue.
This version reconstructs the catalogue from BOTH parts of the saved layout:

- selected summary items: 43
- items removed only from the summary: 103
- complete known catalogue: 146

`removed` now means exactly what it should mean: excluded from the curated Visual Archive summary, but still available in `photo`, `video`, and `escitalopram/collage`.

Subview rules:
- `?view=photo` = every image under `/photography/`
- `?view=video` = every video in the catalogue
- `?view=escitalopram` = every item under `/collage/`

Each subview is automatically repacked from the top and ignores the curated summary coordinates.
