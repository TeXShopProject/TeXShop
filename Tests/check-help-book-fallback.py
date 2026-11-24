#!/usr/bin/env python3
"""Check that Help > TeXShop Help finds a help book of its own in every language of the interface.

Help Viewer looks for the help book in the localization of the system language and does not fall
back to English when that .lproj folder has no TeXShopHelp. Every language of the interface has its
own book in <lang>.lproj/TeXShopHelp, named by CFBundleHelpBookFolder in Info.plist; no
InfoPlist.strings sends a language to the book of another one with CFBundleHelpBookFolder any more.
CFBundleHelpBookName must be the AppleTitle of the book, or Help Viewer does not open it. Each book
has its two indexes (.helpindex and .cshelpindex, built by Scripts/build-help-indexes.sh), and both
have every anchor that the application opens with -[NSHelpManager openHelpAnchor:inBook:].
With --mutation NAME the check runs on a mutated copy and must fail.
"""
from pathlib import Path
import argparse
import copy
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / 'Resources/Interfaces'


def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def apple_title(book):
    raw = (book / 'TeXShop Help.html').read_text(encoding='utf-8')
    match = re.search(r'<META\s+NAME="AppleTitle"\s+CONTENT="([^"]*)"', raw, re.I)
    return match.group(1) if match else None


def index_anchors(index, kind):
    listing = subprocess.run(['hiutil', '-I', kind, '-A', '-f', str(index)], capture_output=True, text=True).stdout
    return {line.strip() for line in listing.splitlines() if line.strip()}


MUTATIONS = {
    # French goes back to the English book.
    'redirected-to-english': lambda tables, books: tables['fr'].__setitem__('CFBundleHelpBookFolder', '../en.lproj/TeXShopHelp'),
    # Japanese, which always had its own book, is redirected too.
    'own-book-redirected': lambda tables, books: tables['ja'].__setitem__('CFBundleHelpBookFolder', '../en.lproj/TeXShopHelp'),
    # The book name differs from the AppleTitle of the Chinese book.
    'wrong-name': lambda tables, books: tables['zh_CN'].__setitem__('CFBundleHelpBookName', 'TeXShop 帮助'),
    # Romanian has no book.
    'no-book': lambda tables, books: books.pop('ro'),
    # The Spanish book has no Help Viewer index.
    'no-index': lambda tables, books: books['es']['indexes'].pop('.helpindex'),
    # The Korean Core Spotlight index lacks the anchor of How to Use Marks.
    'missing-anchor': lambda tables, books: books['ko']['anchors']['.cshelpindex'].discard('marks'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

info = strings(ROOT / 'Resources/Info.plist')
failures = []
folder_name = info.get('CFBundleHelpBookFolder')
if folder_name != 'TeXShopHelp':
    failures.append(f"Info.plist: CFBundleHelpBookFolder is {folder_name!r}, not 'TeXShopHelp'")
    folder_name = 'TeXShopHelp'

# The anchors that the application opens (Edit › Marks › How to Use Marks…, the ? of TEX-root find, …).
sources = '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in (ROOT / 'Sources').rglob('*.m'))
wanted_anchors = set(re.findall(r'openHelpAnchor:@"([^"]+)"', sources))
assert {'marks', 'texroot_search'} <= wanted_anchors, sorted(wanted_anchors)

lprojs = sorted(p for p in INTERFACES.glob('*.lproj') if p.name != 'Base.lproj')
tables, books = {}, {}
for lproj in lprojs:
    table = lproj / 'InfoPlist.strings'
    if not table.exists():
        failures.append(f'{lproj.name}: no InfoPlist.strings, so the help book cannot be named')
        continue
    tables[lproj.stem] = strings(table)
    book = lproj / folder_name
    if book.is_dir():
        indexes = {}
        for suffix, kind in (('.helpindex', 'lsm'), ('.cshelpindex', 'corespotlight')):
            found = sorted(book.glob(f'*{suffix}'))
            if found:
                indexes[suffix] = (found[0], kind)
        books[lproj.stem] = {'path': book, 'indexes': indexes,
                             'anchors': {suffix: index_anchors(path, kind) for suffix, (path, kind) in indexes.items()}}
assert {'en', 'ja', 'fr', 'it', 'zh_CN'} <= set(tables), sorted(tables)


def check(tables, books):
    found = []
    for lang, table in sorted(tables.items()):
        folder = table.get('CFBundleHelpBookFolder')
        if folder is not None:
            found.append(f'{lang}: CFBundleHelpBookFolder names {folder!r}; every language uses its own book')
        if lang not in books:
            found.append(f'{lang}: no {lang}.lproj/{folder_name}, so Help Viewer shows no TeXShop help')
            continue
        book = books[lang]
        name, title = table.get('CFBundleHelpBookName'), apple_title(book['path'])
        if name != title:
            found.append(f'{lang}: CFBundleHelpBookName {name!r} differs from the AppleTitle {title!r} of {book["path"].relative_to(INTERFACES)}')
        for suffix in ('.helpindex', '.cshelpindex'):
            if suffix not in book['indexes']:
                found.append(f'{lang}: the help book has no {suffix} (Scripts/build-help-indexes.sh {lang})')
                continue
            missing = wanted_anchors - book['anchors'][suffix]
            if missing:
                found.append(f'{lang}: {book["indexes"][suffix][0].name} lacks the anchors {", ".join(sorted(missing))}')
    return found


if args.mutation:
    # A mutation must add a failure of its own, also while a book still waits for its indexes.
    baseline = set(check(tables, books))
    tables, books = copy.deepcopy(tables), copy.deepcopy(books)
    MUTATIONS[args.mutation](tables, books)
    failures = [f for f in failures + check(tables, books) if f not in baseline]
else:
    failures += check(tables, books)

if args.mutation:
    assert failures, f'mutation not detected: {args.mutation}'
    print(f'PASS: detected mutation {args.mutation}: {failures[0]}')
    sys.exit(0)
if failures:
    print('FAIL:\n  ' + '\n  '.join(failures))
    sys.exit(1)
print(f'PASS: {len(tables)} languages have their own help book with both indexes and the anchors {", ".join(sorted(wanted_anchors))}')
