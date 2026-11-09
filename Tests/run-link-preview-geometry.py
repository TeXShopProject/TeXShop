#!/usr/bin/env python3
"""Exercise link-preview geometry and PDF drawing without launching TeXShop."""
from pathlib import Path
import subprocess
import tempfile
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="texshop-link-preview-") as directory:
    executable = Path(directory) / "probe"
    subprocess.run([
        "xcrun", "clang", "-fobjc-arc", "-framework", "Cocoa", "-framework", "PDFKit",
        *include_args(root), str(root / "Tests/LinkPreviewGeometry.m"),
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable), str(root / "DocumentSources/Manual Source/Manual.pdf")], check=True)
