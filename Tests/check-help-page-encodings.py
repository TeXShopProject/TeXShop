#!/usr/bin/env python3
"""Check that every help page is written in the character set it declares.

Help Viewer reads a page in the charset of its <meta> tag. A page declared iso-8859-1 that holds
UTF-8 text (curly quotes, accented names, Hangul) shows that text garbled. The Japanese help is
UTF-8, like the rest of the source, so that it can be searched and edited with ordinary tools."""
from pathlib import Path
import argparse
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CHARSET = re.compile(br'charset\s*=\s*["\']?([A-Za-z0-9_\-]+)', re.I)
CODECS = {'utf-8': 'utf-8', 'iso-8859-1': 'latin-1'}


def shift_jis_page(pages):
    """A Japanese page saved back in Shift_JIS, as the Japanese help was before 6.00."""
    path = next(p for p in pages if '/ja.lproj/' in str(p) and p.name == 'basic_edittricks.htm')
    text = pages[path].decode('utf-8').replace('charset=UTF-8', 'charset=Shift_JIS', 1)
    pages[path] = text.encode('cp932')


def utf8_labeled_latin1(pages):
    """An English page with curly quotes whose label says iso-8859-1 (5 pages in 6.00 beta 1)."""
    path = next(p for p in pages if '/en.lproj/' in str(p) and p.name == 'advanced_coloredtext.htm')
    pages[path] = pages[path].replace(b'charset=UTF-8', b'charset=iso-8859-1', 1)


MUTATIONS = {'shift-jis-page': shift_jis_page, 'utf8-labeled-latin1': utf8_labeled_latin1}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

pages = {p: p.read_bytes()
         for p in sorted((ROOT / 'Resources/Interfaces').glob('*.lproj/TeXShopHelp/**/*.htm*'))}
assert len(pages) > 300, len(pages)
if args.mutation:
    MUTATIONS[args.mutation](pages)

failures = []
for path, raw in pages.items():
    name = str(path.relative_to(ROOT))
    labels = [m.decode().lower() for m in CHARSET.findall(raw)]
    ascii_only = all(b < 0x80 for b in raw)
    if len(set(labels)) > 1:
        failures.append(f'{name}: declares {labels}')
        continue
    label = labels[0] if labels else None
    if '/ja.lproj/' in name and label != 'utf-8':
        failures.append(f'{name}: the Japanese help must declare UTF-8, not {label}')
        continue
    if ascii_only:
        continue
    if label not in CODECS:
        failures.append(f'{name}: text beyond ASCII under the charset {label}')
        continue
    try:
        raw.decode(CODECS[label])
    except UnicodeDecodeError as error:
        failures.append(f'{name}: not {label}: {error}')
        continue
    if label == 'iso-8859-1':
        try:
            raw.decode('utf-8')
            failures.append(f'{name}: UTF-8 text declared iso-8859-1 is shown garbled')
        except UnicodeDecodeError:
            pass
        if re.search(rb'[\x80-\x9f]', raw):
            failures.append(f'{name}: bytes 0x80-0x9F are not iso-8859-1 text')

if args.mutation:
    assert failures, 'mutation not detected: ' + args.mutation
    print(f'PASS: detected mutation {args.mutation}: {failures[0]}')
    sys.exit(0)
if failures:
    print('FAIL:\n' + '\n'.join(failures))
    sys.exit(1)
print(f'PASS: all {len(pages)} help pages are written in the charset they declare')
