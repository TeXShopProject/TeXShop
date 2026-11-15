#!/usr/bin/env python3
"""Update the English names of the Unicode blocks that Character Info shows.

  python3 Scripts/update-unicode-block-names.py PATH-TO-Blocks.txt

Blocks.txt is the file of the Unicode Character Database (https://www.unicode.org/Public/UNIDATA/Blocks.txt).
The names are written between the BEGIN and END lines of Sources/Panels/TSUnicodeBlockNames.m. The names in
other languages are not part of TeXShop: they are read from the Character Viewer of macOS at run time.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main(blocks):
    names = [m.group(1).strip() for m in re.finditer(r'^[0-9A-F]+\.\.[0-9A-F]+;\s*(.+)$', Path(blocks).read_text(), re.M)]
    assert names, 'no blocks in ' + blocks
    source = ROOT / 'Sources/Panels/TSUnicodeBlockNames.m'
    text = source.read_text()
    begin, end = '    // BEGIN block names\n', '    // END block names\n'
    listed = ''.join('    @"%s",\n' % name.replace('\\', '\\\\').replace('"', '\\"') for name in sorted(names, key=str.lower))
    source.write_text(text[:text.index(begin) + len(begin)] + listed + text[text.index(end):])
    print(f'{len(names)} blocks')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
