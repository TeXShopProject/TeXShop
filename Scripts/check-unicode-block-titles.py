#!/usr/bin/env python3
"""Check the table of Unicode block names that Character Info reads from macOS.

  python3 Scripts/check-unicode-block-titles.py [TABLE] [--strict]

TABLE defaults to the Character Viewer's table of this Mac:
/System/Library/Input Methods/CharacterPalette.app/Contents/Resources/UnicodeBlocks_Title.loctable

It reports
  1. whether the table exists and can be read (a binary property list {language: {block name: name}});
  2. whether it has the twelve languages of TeXShop (pt is pt_BR, pt-PT is pt_PT);
  3. whether every block name of the table matches a block of ICU (the libicucore of this Mac), as
     Sources/Panels/TSUnicodeBlockNames.m matches them; a name that matches none is a change of naming
     that TeXShop must learn, and its translations are lost until then;
  4. the blocks of ICU that the table does not name (blocks newer than the table): Character Info shows
     their English names.

It exits with a status other than 0 when 1, 2 or 3 fails, and with --strict also when 4 lists a block.
See Documentation/macOS-resources.md.
"""
import argparse
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TABLE = Path('/System/Library/Input Methods/CharacterPalette.app/Contents/Resources/UnicodeBlocks_Title.loctable')
LANGUAGES = {'de': 'de', 'en': 'en', 'es': 'es', 'fr': 'fr', 'it': 'it', 'ja': 'ja', 'ko': 'ko', 'nl': 'nl',
             'pt': 'pt_BR', 'pt-PT': 'pt_PT', 'ro': 'ro', 'zh_CN': 'zh_CN'}
ICU_BLOCKS = r'''
#include <unicode/uchar.h>
#include <stdio.h>
int main(void) {
    UVersionInfo v; u_getUnicodeVersion(v); printf("Unicode %d.%d\n", v[0], v[1]);
    for (int b = 1; b <= u_getIntPropertyMaxValue(UCHAR_BLOCK); b++) {
        const char *name = u_getPropertyValueName(UCHAR_BLOCK, b, U_LONG_PROPERTY_NAME);
        if (name) printf("%s\n", name);
    }
    return 0;
}
'''


def key(name):
    """As TSUnicodeBlockKey: the abbreviations of the table spelled out, then letters and digits in lower case."""
    name = name.lower()
    for short, full in ((r'\bext\.', 'extension'), (r'\bsupp\.', 'supplement'), (r'\bdesc\.', 'description'), (r'\bmath\b', 'mathematical')):
        name = re.sub(short, full, name)
    return re.sub(r'[^a-z0-9]', '', name)


def icu_blocks():
    with tempfile.TemporaryDirectory() as tmp:
        source, binary = Path(tmp) / 'blocks.c', Path(tmp) / 'blocks'
        source.write_text(ICU_BLOCKS)
        subprocess.run(['xcrun', 'clang', str(source), '-licucore', '-o', str(binary)], check=True)
        lines = subprocess.run([str(binary)], capture_output=True, text=True, check=True).stdout.splitlines()
    return lines[0], [line.replace('_', ' ') for line in lines[1:]]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('table', nargs='?', default=str(TABLE))
    parser.add_argument('--strict', action='store_true', help='also fail when a block of ICU has no name in the table')
    args = parser.parse_args()
    problems = 0

    table = Path(args.table)
    try:
        data = plistlib.loads(table.read_bytes())
        assert isinstance(data, dict)
    except Exception as error:
        print(f'FAIL 1: {table} cannot be read as a table of block names ({error.__class__.__name__}: {error})')
        return 1
    print(f'OK 1: {table} is read')

    missing = [f'{folder} ({language})' for folder, language in LANGUAGES.items() if not isinstance(data.get(language), dict)]
    if missing:
        print(f'FAIL 2: languages missing: {", ".join(missing)}')
        problems += 1
    else:
        counts = sorted({len(data[language]) for language in LANGUAGES.values()})
        print(f'OK 2: the twelve languages of TeXShop are there, with {"/".join(map(str, counts))} names')

    unicode, blocks = icu_blocks()
    keys = {key(block) for block in blocks}
    names = {name for language in LANGUAGES.values() if isinstance(data.get(language), dict) for name in data[language] if isinstance(name, str)}
    unknown = sorted(name for name in names if key(name) not in keys)
    if unknown:
        print(f'FAIL 3: {len(unknown)} names of the table match no block of ICU ({unicode}): {unknown}')
        problems += 1
    else:
        print(f'OK 3: all {len(names)} names of the table match a block of ICU ({unicode}, {len(blocks)} blocks)')

    named = {key(name) for name in names}
    english = [block for block in blocks if key(block) not in named]
    print(f'{"FAIL" if english and args.strict else "NOTE"} 4: {len(english)} blocks of ICU have no name in the table and are shown in English'
          + (f': {english}' if english else ''))
    if english and args.strict:
        problems += 1
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
