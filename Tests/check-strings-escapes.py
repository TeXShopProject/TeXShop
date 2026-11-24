#!/usr/bin/env python3
"""Every backslash in the quoted text of a .strings file starts an escape that Foundation reads.

Foundation drops the backslash of an escape it does not know: "ShiftJIS \\)" became "ShiftJIS )" in the
encoding menus until 6.00, and "\\n\\Characters" lost its second line break. A backslash that is meant to
be shown is written "\\\\". Comments are not read. The check covers the .strings files of every language
under Resources, and it checks itself on those two examples.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[^\s"/]+|/', re.S)
# \a \b \f \n \r \t \v, quotes, the backslash, \Uhhhh and octal digits, as the property list parser reads them.
ESCAPE = re.compile(r'\\(.)', re.S)
KNOWN = set('abfnrtv"\'\\U01234567')


def unknown_escapes(text):
    found = []
    for match in TOKEN.finditer(text):
        token = match.group()
        if not token.startswith('"'):
            continue
        for escape in ESCAPE.finditer(token):
            if escape.group(1) not in KNOWN:
                line = text.count('\n', 0, match.start() + escape.start()) + 1
                found.append((line, token[max(0, escape.start() - 20):escape.end() + 10]))
    return found


def read(path):
    data = path.read_bytes()
    if data.startswith(b'bplist') or data.lstrip().startswith(b'<?xml'):
        return None
    return data.decode('utf-16' if data[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8-sig')


def main():
    assert [line for line, _ in unknown_escapes('/* \\d and \\w */\n"DOSJapanese" = "Japanese (ShiftJIS \\)";\n')] == [2]
    assert unknown_escapes('"x" = "%@\\n\\nCharacters: %d \\\\) \\U00e9 \\"q\\"";') == []
    assert len(unknown_escapes('"x" = "%@\\n\\Characters: %d";')) == 1
    failures, count = [], 0
    for path in sorted((ROOT / 'Resources').rglob('*.strings')):
        text = read(path)
        if text is None:
            continue
        count += 1
        for line, excerpt in unknown_escapes(text):
            failures.append(f'{path.relative_to(ROOT)}:{line}: {excerpt}')
    if failures:
        print('\n'.join('FAIL: unknown escape, its backslash is dropped: ' + failure for failure in failures))
        sys.exit(1)
    print(f'PASS: {count} .strings files use only escapes that Foundation reads')


if __name__ == '__main__':
    main()
