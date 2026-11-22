#!/usr/bin/env python3
"""Write the side menu and the chapter name of every page of the help books.

Each chapter of a help book (basic, advanced, configure, macros) has a contents page,
pgs/<chapter>.htm, whose <h1> is the chapter name and whose <ul class="toc"> lists its
pages in order. Every page whose name starts with "<chapter>_", and the contents page
itself, gets that list as its <nav id="menu">, with its own entry marked, and the chapter
name in its header. Run it after adding, removing, renaming or retitling a page.

  python3 Scripts/update-help-navigation.py          # rewrite the pages
  python3 Scripts/update-help-navigation.py --check  # list pages that are out of date
"""
from pathlib import Path
import argparse
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CHAPTERS = ('basic', 'advanced', 'configure', 'macros')


def books():
    return sorted(p for p in (ROOT / 'Resources/Interfaces').glob('*.lproj/TeXShopHelp') if (p / 'pgs').is_dir())


def contents(page):
    text = page.read_text(encoding='utf-8')
    title = re.search(r'<h1>(.*?)</h1>', text, re.S)
    toc = re.search(r'<ul class="toc">(.*?)</ul>', text, re.S)
    if not title or not toc:
        raise SystemExit(f'{page}: a contents page needs an <h1> and a <ul class="toc">')
    entries = re.findall(r'<a href="([^"#]+)">(.*?)</a>', toc.group(1), re.S)
    return title.group(1).strip(), [(href, re.sub(r'\s+', ' ', label).strip()) for href, label in entries]


def menu(entries, current):
    lines = ['<nav id="menu">', '<ul>']
    for href, label in entries:
        mark = ' class="current"' if href == current else ''
        lines.append(f'<li><a href="{href}"{mark}>{label}</a></li>')
    lines += ['</ul>', '</nav>']
    return '\n'.join(lines)


def updated(text, chapter, entries, name):
    text = re.sub(r'<nav id="menu">.*?</nav>', lambda m: menu(entries, name), text, count=1, flags=re.S)
    return re.sub(r'(<span class="chapter">).*?(</span>)', lambda m: m.group(1) + chapter + m.group(2), text, count=1, flags=re.S)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='change nothing; exit 1 if a page is out of date')
    args = parser.parse_args()
    stale = []
    for book in books():
        for chapter_name in CHAPTERS:
            page = book / 'pgs' / f'{chapter_name}.htm'
            if not page.exists():
                continue
            chapter, entries = contents(page)
            for path in sorted(book.glob(f'pgs/{chapter_name}*.htm')):
                if path.stem != chapter_name and not path.stem.startswith(chapter_name + '_'):
                    continue
                text = path.read_text(encoding='utf-8')
                if '<nav id="menu">' not in text:
                    stale.append(f'{path.relative_to(ROOT)}: no <nav id="menu">')
                    continue
                new = updated(text, chapter, entries, path.name)
                if new != text:
                    stale.append(str(path.relative_to(ROOT)))
                    if not args.check:
                        path.write_text(new, encoding='utf-8')
    if args.check and stale:
        print('\n'.join(stale))
        sys.exit(1)
    if not args.check:
        print(f'{len(stale)} pages updated')


if __name__ == '__main__':
    main()
