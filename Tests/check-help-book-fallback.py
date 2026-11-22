#!/usr/bin/env python3
"""Check that Help > TeXShop Help Panel finds a help book in every language of the interface.

Help Viewer looks for the help book in the localization of the system language. A language
whose .lproj folder has no TeXShopHelp gets no book at all: Help Viewer does not fall back to
English, while a language without any .lproj folder does get the English book. Every language
without its own book therefore names the English book in its InfoPlist.strings with
CFBundleHelpBookFolder, a path relative to its .lproj folder. CFBundleHelpBookName must be the
AppleTitle of the book that is found, or Help Viewer does not open it.
"""
from pathlib import Path
import argparse
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


MUTATIONS = {
    # French without the folder key: Help Viewer finds no book.
    'no-folder': lambda tables: tables['fr'].pop('CFBundleHelpBookFolder'),
    # The folder key names a book that does not exist.
    'missing-folder': lambda tables: tables['it'].__setitem__('CFBundleHelpBookFolder', '../en.lproj/Help'),
    # The book name differs from the AppleTitle of the English book.
    'wrong-name': lambda tables: tables['zh_CN'].__setitem__('CFBundleHelpBookName', 'TeXShop 帮助'),
    # A language with its own book also redirects to another one.
    'own-book-redirected': lambda tables: tables['ja'].__setitem__('CFBundleHelpBookFolder', '../en.lproj/TeXShopHelp'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

info = strings(ROOT / 'Resources/Info.plist')
failures = []
if info.get('CFBundleHelpBookFolder') != 'TeXShopHelp':
    failures.append(f"Info.plist: CFBundleHelpBookFolder is {info.get('CFBundleHelpBookFolder')!r}, not 'TeXShopHelp'")

lprojs = sorted(p for p in INTERFACES.glob('*.lproj') if p.name != 'Base.lproj')
tables = {}
for lproj in lprojs:
    table = lproj / 'InfoPlist.strings'
    if not table.exists():
        failures.append(f'{lproj.name}: no InfoPlist.strings, so the help book cannot be named')
        continue
    tables[lproj.stem] = strings(table)
assert {'en', 'ja', 'fr', 'it', 'zh_CN'} <= set(tables), sorted(tables)
if args.mutation:
    MUTATIONS[args.mutation](tables)

without_book = []
for lang, table in tables.items():
    lproj = INTERFACES / f'{lang}.lproj'
    own = lproj / info['CFBundleHelpBookFolder']
    folder = table.get('CFBundleHelpBookFolder')
    if own.is_dir():
        book = own
        if folder is not None:
            failures.append(f'{lang}: has its own help book but CFBundleHelpBookFolder names {folder!r}')
            continue
    else:
        without_book.append(lang)
        if folder is None:
            failures.append(f'{lang}: no help book and no CFBundleHelpBookFolder, so Help Viewer shows no TeXShop help')
            continue
        book = (lproj / folder).resolve()
        if not re.fullmatch(r'\.\./[A-Za-z_-]+\.lproj/TeXShopHelp', folder) or not (book / 'TeXShop Help.html').is_file():
            failures.append(f'{lang}: CFBundleHelpBookFolder {folder!r} is not a help book of another language')
            continue
    name, title = table.get('CFBundleHelpBookName'), apple_title(book)
    if name != title:
        failures.append(f'{lang}: CFBundleHelpBookName {name!r} differs from the AppleTitle {title!r} of {book.relative_to(INTERFACES)}')

if args.mutation:
    assert failures, f'mutation not detected: {args.mutation}'
    print(f'PASS: detected mutation {args.mutation}: {failures[0]}')
    sys.exit(0)
if failures:
    print('FAIL:\n  ' + '\n  '.join(failures))
    sys.exit(1)
print(f'PASS: {len(tables)} languages find a help book; {len(without_book)} use the English one ({", ".join(sorted(without_book))})')
