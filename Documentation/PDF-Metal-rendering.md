# Workaround for PDF line-rendering Metal aborts on macOS 27 (2026-10-13)

## Reproduction

The TeXShop 5.58.9 crash report shows SIGABRT in MetalTools validateCommonDrawErrors, reached through CA::OGL::MetalContext::stroke_lines and WideLineRenderer. The main thread is waiting for events; this is not an Objective-C exception in TeXShop.

The supplied 30-page PDF passes qpdf's syntax check. A standalone standard PDFView with no TeXShop code reproduces the abort around page 14 with MTL_DEBUG_LAYER=1:

```
instanceCount(0) must be non-zero.
```

This isolates the failure to the PDFKit/QuartzCore GPU line-rendering path, rather than company-specific code. The reason the OS generates the invalid draw command is unknown. No comparison on an older OS has established when the defect was introduced.

## Workaround

MyPDFKitView implements drawPage:toContext:. On macOS 27 or later, only contexts identified as screen drawing by NSGraphicsContext use CPU bitmap rendering. The existing drawPage: method draws into bitmap tiles, which are then copied to the screen, avoiding GPU vector strokes.

TSPDFScreenRendering.h transforms the clip into device coordinates and processes tiles of at most 1024 by 1024 pixels (approximately 4 MiB per pixel buffer). This retains scale, rotation, and Retina resolution. The source PDF and its text are unchanged. Non-screen drawing, including vector printing, and macOS 26 or earlier retain the existing drawing path.

Metal validation remains enabled during testing. CPU load may increase for complex pages. Reassess the workaround when the OS rendering defect is fixed.

## Validation

Tests/run-pdf-screen-rendering.py extracts the new method and uses the real header in an independent PDFView. It does not initialize TeXShop or change user documents or preferences.

- All 30 pages of the supplied PDF render with Metal validation enabled; the standard PDFView control aborts with the same input.
- CPU reference and tiled pixels match for scaling, 0/90/180/270-degree rotation, clipping, and drawing across tile boundaries.
- PDF output resources contain no raster image objects on the printing path.
- Company and international Debug and Release builds succeeded. The company universal Release passed strict deep code-signature verification.

The harness uses standard PDFPage drawing in place of TeXShop's legacy drawPage: implementation; application-specific synchronization marks are not covered. Full application GUI behavior and execution on older operating systems have not been verified.
