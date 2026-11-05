# TeXShop app icon

Prepared from the maintainer’s vector artwork at the maintainer's request.
The Japanese character has been removed. The outlined TeX mark is centered
at (512, 512) on a 1024-unit canvas. The mark is fitted to a height of
390 units, then expanded by 4 units along its contour to improve legibility
at small sizes. The resulting outline is shared by the SVG and raster assets.
The inherited gray-green gradient, white lettering, bevel, and shadow are retained.
A 48-unit white rim recalls the classic circular icon, following the rounded-square
outline. Its white-to-silver gradient gives the edge subtle depth without reducing
the enlarged lettering. `Frame.svg` supplies the rim and inset background.

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

The Xcode target uses `TeXShop.icon` and the app-icon name `TeXShop`.
The root `icon.icns` retains the legacy fallback. The website uses the generated PNG,
and the Organization avatar uses `GitHub-avatar.png`.
