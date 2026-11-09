# TeXShop app icon

The gray-green background and subtle relief continue the existing artwork.
The lettering is traced from the classic round icon in
`Resources/DockIcons/round.png`, retaining its glyph shapes rather than
substituting a different font. No additional weight expansion is applied.
On the 1024-pixel fallback canvas, the lettering occupies approximately
663 × 343 pixels, matching the classic icon. It is shifted 4 pixels to the
right for optical centering (0.5 pixels at a 128-pixel display size); its vertical
position is unchanged.

The white-frame design (C) adds a 48-unit rim on the full-bleed artwork canvas.
Its white-to-silver gradient gives the edge subtle depth. The inner edge of the rim
and its highlight follow the outer shape that macOS 26 and later give app icons,
moved inward by 48 and 3 units, so the rim keeps its width round the corners; that
shape is not a circular arc. The fallback artwork uses the same outer shape. On the fallback
canvas, approximately 46 pixels on the left and 38 pixels on the right separate
the lettering from the inner edge of the frame. The unframed design (B) uses the same
lettering and placement.

- `TeXShop.icon`: Icon Composer source; macOS supplies the outer mask. Its
  layer list runs front to back: lettering first, opaque frame last. Verify
  the built app’s `Contents/Resources/TeXShop.icns` as well as the PNG preview.
- `TeXShop.icns`: Legacy rounded-square fallback.
- `Icon-preview.png`: Fallback preview including standard icon padding.
- `GitHub-avatar.png`: Full-bleed square avatar.
- `TeXShop.iconset`: Legacy raster sizes.
- `Classic-TeX-outline.json`: Traced classic lettering, in original canvas coordinates.
- `Icon-mask-outline.json`: The macOS 26 icon shape, and the same shape moved inward
  by the rim and its highlight, recorded by `trace-icon-mask.py` from an Icon
  Composer export.
- `TeX-logo-outline.json`: Earlier lettering from the maintainer’s vector artwork,
  retained for provenance but no longer used by the generator.

Regenerate the white-frame design on macOS 13 or later from the repository root:

```sh
swift Artwork/generate-icon.swift
iconutil -c icns Artwork/TeXShop.iconset -o Artwork/TeXShop.icns
```

Copy `Artwork/Icon-preview.png` to `Resources/DockIcons/current.png`. If a new macOS changes the icon shape, run
`python3 Artwork/trace-icon-mask.py` (Xcode 26 or later, Pillow, NumPy and SciPy)
before the Swift command.

Add `--no-frame` to the Swift command to generate B instead. The command also
updates the Icon Composer layer selection. To retrace the lettering, use
`python3 Artwork/trace-classic-lettering.py`; its dependencies are documented
in the script. Ordinary regeneration uses the stored outlines and needs no
tracing dependencies.

The Xcode target uses `TeXShop.icon` and the app-icon name `TeXShop`.
`Resources/DockIcons/current.png` is a copy of the chosen fallback. Website and published avatar updates are separate.
