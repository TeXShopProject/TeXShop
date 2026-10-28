# TeXShop icon proposal

Prepared from the TetsuTeXShop vector artwork at the maintainer's request.
The Japanese character has been removed. The outlined TeX mark is centered
at (512, 512) on a 1024-unit canvas, with a height of 340 units.
The inherited gray-green gradient, white lettering, bevel, and shadow are retained.

- `TeXShop.icon`: Icon Composer source. The background fills the entire canvas;
  macOS supplies the app-icon mask. There is no circle inside an additional tile.
- `TeXShop.icns`: Legacy rounded-square fallback.
- `Icon-preview.png`: Preview of that fallback, including standard icon padding.
- `GitHub-avatar.png`: Full-bleed 1024-pixel square for the Organization/repository avatar.
- `TeXShop.iconset`: Legacy raster sizes, also used for the website icon.
- `TeX-logo-outline.json`: Font-independent outlines inherited from the company artwork.

Regenerate on macOS 13 or later from the repository root:

```sh
swift Artwork/generate-icon.swift
iconutil -c icns Artwork/TeXShop.iconset -o Artwork/TeXShop.icns
```

This proposal is not yet wired into the Xcode app-icon build settings.
Actual macOS app-icon rendering must be checked when it is integrated.
The website preview uses the generated legacy PNG. No GitHub avatar has been uploaded.
