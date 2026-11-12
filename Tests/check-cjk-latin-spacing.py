#!/usr/bin/env python3
"""Japanese and Chinese interface text has no space between CJK and Latin letters or digits.

macOS writes these languages without such a space and adds the visual gap when it draws
the text. Korean separates words with spaces, so it is not checked. The help pages and
the historical Preferences.nib are not interface text in use.
"""
from pathlib import Path
import re, sys

root = Path(__file__).resolve().parents[1]
CJK = '[　-〿぀-ヿ㐀-鿿！-｠]'
spaced = re.compile(f'{CJK} [A-Za-z0-9]|[A-Za-z0-9] {CJK}')

def interface_files(language):
    for path in sorted((root / 'Resources/Interfaces' / f'{language}.lproj').rglob('*')):
        text = str(path)
        if 'TeXShopHelp' in text or 'Preferences.nib' in text:
            continue
        if path.name.endswith('.strings') or path.name == 'designable.nib' or path.suffix == '.xib':
            yield path

def unescape(text):
    # .strings files may write characters as \Uxxxx.
    return re.sub(r'\\U([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), text)

def read(path):
    raw = path.read_bytes()
    return unescape(raw.decode('utf-16' if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8'))

mutation = sys.argv[1] if len(sys.argv) > 1 else ''
failures, files = [], 0
for language in ('ja', 'zh_CN'):
    for path in interface_files(language):
        files += 1
        text = read(path)
        if mutation == 'spaced-menu' and language == 'ja' and path.parent.name == 'MainMenu.nib':
            text = text.replace('TeXShopを終了', 'TeXShop を終了')
        if mutation == 'spaced-chinese' and language == 'zh_CN' and path.name == 'Localizable.strings':
            text += '\n"Mutation" = "PDF 文件";'
        if mutation == 'spaced-escape' and language == 'zh_CN' and path.name == 'ToolbarItems.strings':
            text += unescape('\n"Mutation" = "TeXShop \\U6f14\\U793a";')
        for match in spaced.finditer(text):
            line = text.count('\n', 0, match.start()) + 1
            failures.append(f'{path.relative_to(root)}:{line}: {text[max(0, match.start() - 12):match.end() + 12]!r}')

# Compiled nibs carry the same titles; some exist only in compiled form.
import plistlib
compiled = 0
for language in ('ja', 'zh_CN'):
    for path in sorted((root / 'Resources/Interfaces' / f'{language}.lproj').rglob('*.nib')):
        if path.is_dir() or 'Preferences.nib' in path.parts or 'TeXShopHelp' in path.parts:
            continue
        data = path.read_bytes()
        compiled += 1
        if data.startswith(b'bplist'):
            texts = [o for o in plistlib.loads(data)['$objects'] if isinstance(o, str)]
        else:
            texts = [data.decode('utf-8', 'ignore')]
        if mutation == 'spaced-compiled' and language == 'zh_CN' and path.parent.name == 'MainMenu.nib' and path.name == 'keyedobjects.nib':
            texts.append('TeXShop 演示')
        for text in texts:
            for match in spaced.finditer(text):
                failures.append(f'{path.relative_to(root)}: {text[max(0, match.start() - 12):match.end() + 12]!r}')
assert compiled > 40, compiled

# Korean keeps its word spacing.
korean = read(root / 'Resources/Interfaces/ko.lproj/SettingsCategories.strings')
assert re.search('[A-Za-z0-9] [가-힯]', korean), 'Korean interface text keeps spaces between words'
assert files > 40, files

if mutation:
    if not failures:
        raise SystemExit(f'FAIL: mutation {mutation} was not detected')
    print('detected mutation', mutation)
elif failures:
    raise SystemExit('Space between CJK and Latin text:\n' + '\n'.join(failures))
else:
    print(f'PASS: {files} Japanese and Chinese interface sources and {compiled} compiled nibs have no space between CJK and Latin text; Korean keeps word spacing')
