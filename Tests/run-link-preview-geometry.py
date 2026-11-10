#!/usr/bin/env python3
"""Exercise link-preview geometry and PDF drawing without launching TeXShop."""
from pathlib import Path
import argparse
import subprocess
import tempfile
from source_tree import include_args

MUTATIONS = {
    'move-unclamped': ('    up.origin = NSMakePoint(x, y);\n', '    up.origin = NSMakePoint(NSMinX(up) + delta.width, NSMinY(up) + (flipped ? -delta.height : delta.height));\n'),
    'resize-anchor': ('        source.origin.x += change / sx; source.size.width -= change / sx;\n', '        source.size.width -= change / sx;\n'),
    'resize-minimum': ('NSMaxX(up) - minimum.width);', 'NSMaxX(up));'),
    'pan-unclamped': ('    source.origin.x = TSLinkPreviewClamp(NSMinX(source) - contentDelta.width, 0,\n                                         MAX(0, pageSize.width - NSWidth(source)));\n',
                      '    source.origin.x = NSMinX(source) - contentDelta.width;\n'),
    'edge-orientation': ('    if (flipped) point.y = -point.y;\n    grip', '    grip'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="texshop-link-preview-") as directory:
    executable = Path(directory) / "probe"
    includes = include_args(root)
    if args.mutation:
        header = (root / "Sources/Preview/TSLinkPreviewGeometry.h").read_text()
        old, new = MUTATIONS[args.mutation]
        assert header.count(old) == 1, args.mutation
        (Path(directory) / "TSLinkPreviewGeometry.h").write_text(header.replace(old, new))
        includes = ['-I', directory, *includes]
    subprocess.run([
        "xcrun", "clang", "-fobjc-arc", "-framework", "Cocoa", "-framework", "PDFKit",
        *includes, str(root / "Tests/LinkPreviewGeometry.m"),
        "-o", str(executable),
    ], check=True)
    result = subprocess.run([str(executable), str(root / "DocumentSources/Manual Source/Manual.pdf")],
                            capture_output=True, text=True)
    print(result.stdout, end='')
    if args.mutation:
        assert result.returncode != 0, 'mutation %s was not detected' % args.mutation
        print('PASS: detected mutation %s (%s)' % (args.mutation, result.stderr.strip()))
    else:
        print(result.stderr, end='')
        result.check_returncode()
