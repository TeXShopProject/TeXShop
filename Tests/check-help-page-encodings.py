#!/usr/bin/env python3
"""Check that every help page is written in the character set it declares.

Help Viewer reads a page in the charset of its <meta> tag. A page declared iso-8859-1 that holds
UTF-8 text (curly quotes, accented names, Hangul) shows that text garbled. Every help book is
UTF-8, like the rest of the source, so that it can be searched and edited with ordinary tools; the
Japanese book and the books of fr, it, nl, pt, pt-PT, ro and zh_CN must declare it."""
from pathlib import Path
import argparse
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CHARSET = re.compile(br'charset\s*=\s*["\']?([A-Za-z0-9_\-]+)', re.I)
CODECS = {'utf-8': 'utf-8', 'iso-8859-1': 'latin-1'}


def relabel(text, charset):
    """The page with its charset label changed; the mutation must change it."""
    new, count = re.subn(r'charset\s*=\s*["\']?utf-8["\']?', f'charset="{charset}"', text, count=1, flags=re.I)
    assert count == 1, 'no charset label to mutate'
    return new


def shift_jis_page(pages):
    """A Japanese page saved back in Shift_JIS, as the Japanese help was before 6.00."""
    path = next(p for p in pages if '/ja.lproj/' in str(p) and p.name == 'basic_edittricks.htm')
    text = relabel(pages[path].decode('utf-8'), 'Shift_JIS')
    pages[path] = text.encode('cp932', errors='xmlcharrefreplace')


def utf8_labeled_latin1(pages):
    """An English page with curly quotes whose label says iso-8859-1 (5 pages in 6.00 beta 1)."""
    path = next(p for p in pages if '/en.lproj/' in str(p) and p.name == 'advanced_coloredtext.htm')
    pages[path] = relabel(pages[path].decode('utf-8'), 'iso-8859-1').encode('utf-8')


def latin1_translation(pages):
    """A page of a translated book saved in Latin-1 under its own label."""
    path = next(p for p in pages if '/fr.lproj/' in str(p) and p.name == 'basic_printing.htm')
    text = relabel(pages[path].decode('utf-8'), 'iso-8859-1')
    pages[path] = (text + '<!-- é -->').encode('latin-1', errors='replace')


# Books that must declare UTF-8 (the others are UTF-8 today too; check-help-book-structure.py requires it of all).
UTF8_BOOKS = ('ja', 'fr', 'it', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN')
MUTATIONS = {'shift-jis-page': shift_jis_page, 'utf8-labeled-latin1': utf8_labeled_latin1, 'latin1-translation': latin1_translation}
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
    book = path.relative_to(ROOT / 'Resources/Interfaces').parts[0][:-len('.lproj')]
    if book in UTF8_BOOKS and label != 'utf-8':
        failures.append(f'{name}: the {book} help must declare UTF-8, not {label}')
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
