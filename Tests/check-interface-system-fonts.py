#!/usr/bin/env python3
"""Interface text uses the macOS system font in every language.

Interface Builder sources may not name a font (they use metaFont), and compiled
nibs without a source, including those in the NIBArchive format that AppKit reads
from keyedobjects-101300.nib, may not archive a named font for controls. Text views get
their fonts from the user's settings at run time and are not checked here."""
from pathlib import Path
import plistlib
import re
import struct

root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
problems = []
sources = sorted(interfaces.glob('*.lproj/*.nib/designable.nib')) + sorted(interfaces.glob('*.lproj/*.xib'))
for path in sources:
    if path.parent.name == 'Preferences.nib':
        continue  # historical; not built
    for match in re.finditer(r'<font [^>]*\bname="([^"]+)"', path.read_text(encoding='utf-8')):
        problems.append(f'{path.relative_to(root)}: {match.group(1)}')
compiled = 0
for path in sorted(interfaces.glob('*.lproj/*.nib')) + sorted(interfaces.glob('*.lproj/*.nib/keyedobjects*.nib')):
    if path.is_dir() or 'Preferences.nib' in path.parts:
        continue
    data = path.read_bytes()
    if not data.startswith(b'bplist'):
        continue  # compiled by current Interface Builder from a checked source
    compiled += 1
    objects = plistlib.loads(data)['$objects']
    for item in objects:
        if isinstance(item, dict) and 'NSName' in item and 'NSSize' in item and item.get('NSfFlags') == 16:
            name = objects[item['NSName'].data]
            if not name.startswith('.'):  # .AppleSystemUIFont and older system font names
                problems.append(f'{path.relative_to(root)}: {name} {item["NSSize"]:g}')


def varint(data, index):
    """A NIBArchive number: 7 bits a byte, the last byte with its high bit set."""
    value = shift = 0
    while True:
        byte = data[index]
        index += 1
        value |= (byte & 0x7f) << shift
        shift += 7
        if byte & 0x80:
            return value, index


def nib_archive_fonts(data):
    """The fonts (name, size, flags) of a nib in Interface Builder's NIBArchive format, which AppKit reads from
    keyedobjects-101300.nib on macOS 10.13 and later."""
    objects_count, objects_at, keys_count, keys_at, values_count, values_at, classes_count, classes_at = struct.unpack_from('<8I', data, 18)
    keys, classes, values, objects = [], [], [], []
    index = keys_at
    for _ in range(keys_count):
        length, index = varint(data, index)
        keys.append(data[index:index + length].decode())
        index += length
    index = classes_at
    for _ in range(classes_count):
        length, index = varint(data, index)
        extra, index = varint(data, index)
        index += 4 * extra
        classes.append(data[index:index + length].rstrip(b'\0').decode())
        index += length
    index = values_at
    sizes = {0: ('<b', 1), 1: ('<h', 2), 2: ('<i', 4), 3: ('<q', 8), 6: ('<f', 4), 7: ('<d', 8), 10: ('<I', 4)}
    for _ in range(values_count):
        key, index = varint(data, index)
        kind = data[index]
        index += 1
        if kind == 8:
            length, index = varint(data, index)
            value = data[index:index + length]
            index += length
        elif kind in (4, 5, 9):
            value = None
        else:
            form, length = sizes[kind]
            value = struct.unpack_from(form, data, index)[0]
            index += length
            if kind == 10:
                value = ('object', value)
        values.append((keys[key], value))
    index = objects_at
    for _ in range(objects_count):
        cls, index = varint(data, index)
        first, index = varint(data, index)
        count, index = varint(data, index)
        objects.append((classes[cls], dict(values[first:first + count])))
    for cls, fields in objects:
        if cls == 'NSFont' and isinstance(fields.get('NSName'), tuple):
            name = objects[fields['NSName'][1]][1].get('NS.bytes', b'').decode('utf-8', 'replace')
            yield name, fields.get('NSSize'), fields.get('NSfFlags')


# Nibs whose named fonts the code replaces with the system font as it loads them, and the check of that.
REPLACED_AT_LOAD = {
    'zh_CN.lproj/MacroEditor.nib': '-[TSMacroEditor useSystemFont], checked by run-macro-shortcut-layout.py',
}
archives = 0
for path in sorted(interfaces.glob('*.lproj/*.nib/keyedobjects*.nib')):
    if 'Preferences.nib' in path.parts:
        continue
    data = path.read_bytes()
    if not data.startswith(b'NIBArchive'):
        continue
    archives += 1
    for name, size, flags in nib_archive_fonts(data):
        if flags == 16 and not name.startswith('.'):
            nib = '/'.join(path.parts[-3:-1])
            if nib not in REPLACED_AT_LOAD:
                problems.append(f'{path.relative_to(root)}: {name} {size:g}')
assert archives > 0, 'no NIBArchive nibs were read'
assert not problems, 'Named interface fonts:\n' + '\n'.join(problems)
print(f'PASS: {len(sources)} interface sources, {compiled} older compiled nibs and {archives} NIBArchive nibs use the system font'
      f' (named fonts replaced at load: {", ".join(REPLACED_AT_LOAD)})')
