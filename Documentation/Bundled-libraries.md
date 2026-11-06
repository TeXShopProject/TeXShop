# Bundled libraries

Checked against upstream on November 6, 2026. The entries below describe the
libraries actually linked by the TeXShop target, not every historical copy kept
in `3rdparty/`.

| Component | Version | Used files | Upstream |
| --- | --- | --- | --- |
| Sparkle | 2.10.1 (2065) | `Sparkle.framework` | [2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1) |
| OgreKit | 2.1.12 | `OgreKit.framework` | [2.1.12](https://github.com/sonoisa/OgreKit/tree/2.1.12) |
| Onigmo | 6.2.0 | Embedded in OgreKit | [6.2.0](https://github.com/k-takata/Onigmo/releases/tag/Onigmo-6.2.0) |
| zlib | 1.4 | `Resources/Binaries/libz.a` | [1.4](https://github.com/madler/zlib/releases/tag/v1.4) |
| SyncTeX parser | 1.21 | `Sources/synctex_parser*`, `Sources/synctex_version.h` | [TeX Live sources](https://github.com/TeX-Live/texlive-source/tree/a399fb5f3f02441b040ad34c7aed3a1af8ffdc39/texk/web2c/synctexdir) |

## zlib

See `3rdparty/zlib/README.md` for the source archive URL, checksum and rebuild
command. Both target configurations explicitly use the matching vendored headers.
`Scripts/build-zlib.py` builds and tests arm64 and x86_64 before replacing the
static archives. Upstream source is preserved without edits.

## SyncTeX

The parser and utility source files are copied without edits from TeX Live commit
`a399fb5f3f02441b040ad34c7aed3a1af8ffdc39`. Their individual checksums are recorded
in `Documentation/SyncTeX-source.json`. The upstream readme and license notices
are retained in `Sources/synctex_parser_readme.md` and the source headers.
TeXShop uses the standalone configuration, without `SYNCTEX_USE_LOCAL_HEADER`;
TeX Live's engine-specific `synctex_parser_local.h` is not required.

The earlier local correction for magnifications below 1000 is present in upstream
1.21 (floating-point division by `1000.0`). The old parser in
`synctex_parser_old.c/.h` remains available for documents requesting
`% !TEX useOldSyncParser`. It shares the updated utility code and zlib.
The historical command-line SyncTeX executables are separate from this parser
update and are not replaced.

Run `python3 Tests/run-synctex-parser.py` to check forward and inverse queries
using LuaLaTeX and pdfTeX, compressed and uncompressed data, Unicode/space-containing
paths, reduced magnification, and missing/invalid input. It runs the current and
legacy parsers on both architectures. Set `TEXLIVE_BIN` if TeX Live is installed
elsewhere. Intel execution on Apple Silicon requires Rosetta.

## OgreKit and Sparkle

Do not infer OgreKit's recency from the largest version number: upstream tag
`3.0.2` points to `7f7ab1e452336fb73f23fcc57451e61919f87b3d` (2018), whereas
`2.1.12` points to `6bcba98650d3099bec84fa33443e6e0d8856a1bd` (2022).
The upstream README currently offers 2.1.12. The bundled framework reports
2.1.12 and its Onigmo headers report 6.2.0; neither is replaced by the older
`3rdparty/FlipUniversal/OgreKit-3.0.2` sources.

The root Sparkle framework is the one linked and embedded by the target.
`3rdparty/Sparkle-1.24.0` is a historical copy and is not the shipped updater.

Apple frameworks such as PDFKit, AppKit and WebKit are provided by macOS. The
Spotlight importer and adapted NoodleKit source are maintained as part of this
project rather than replaced with a third-party binary during library updates.
