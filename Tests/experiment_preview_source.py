"""Definitions that ScrapPDFKitView.m takes from globals.h/.m, for harnesses that
compile the Experiment preview without the application's globals.

The enums, JPEG factors and defaults key names are copied from the current
sources, so the harnesses follow any change to them.
"""
import re
from pathlib import Path

KEYS = ('ExperimentMouseModeKey', 'PdfCopyTypeKey', 'PdfKitMouseModeKey')


def prelude(root):
    root = Path(root)
    header = (root/'Sources/App/globals.h').read_bytes().decode('latin-1')
    body = (root/'Sources/App/globals.m').read_bytes().decode('latin-1')
    parts = ['#import <Cocoa/Cocoa.h>']
    for name in ('_NewMouseMode', 'ImageCopyType'):
        match = re.search(r'(typedef\s+)?enum\s+' + name + r'\s*\{.*?\}\s*\w*\s*;', header, re.S)
        assert match, 'globals.h enum ' + name
        parts.append(match.group(0))
    jpeg = re.findall(r'^#define JPEG_COMPRESSION_\w+\s+[\d.]+', header, re.M)
    assert len(jpeg) == 3, 'globals.h JPEG factors'
    parts += jpeg
    for key in KEYS:
        match = re.search(r'NSString \*' + key + r' = (@"[^"]+");', body)
        assert match, 'globals.m ' + key
        parts.append('static NSString *%s = %s;' % (key, match.group(1)))
    return '\n'.join(parts) + '\n'


def sources(root):
    """Production files the Experiment preview needs at link time."""
    return [str(Path(root)/'Sources/Preview/OverView.m')]
