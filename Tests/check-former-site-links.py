#!/usr/bin/env python3
"""Check that nothing TeXShop ships leads to Richard Koch's former web site.

The former site (pages.uoregon.edu/koch, www.uoregon.edu/~koch) may go away at any
time; texshop.app keeps an archive of it. The application, its help, its documents,
macros and templates therefore neither link to it nor send readers there, and the
help gives GitHub issues as the place for bug reports. Plain text in the history of
earlier versions (What's New in the help, Changes, About This Release) may still
quote the old addresses as a record, but never as a link.

The vendored filltex project keeps its upstream README and bibliography unchanged.
"""
import argparse, re, sys
from pathlib import Path
from pypdf import PdfReader

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['help-link', 'macro', 'source', 'bug-contact'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

FORMER = re.compile(r'(pages\.uoregon\.edu/koch|uoregon\.edu/~koch|darkwing\.uoregon\.edu|koch@(?:math\.)?uoregon\.edu)', re.I)
LINK = re.compile(r'''(href\s*=\s*["']?[^"'>\s]*|\\(?:url|href)\{[^}]*|open location "[^"]*)''' + FORMER.pattern, re.I)
VENDORED = root/'Resources/TeXShop/Engines/Inactive/filltex/filltex-master'
INDEXES = ('.helpindex', '.cshelpindex')


def history(path):
    # Records of earlier versions may quote the old addresses as plain text.
    return path.name.startswith('whatisnew') or path.stem in ('About This Release', 'Changes')


def text_of(path):
    data = path.read_bytes()
    if args.mutation == 'help-link' and path.match('en.lproj/TeXShopHelp/pgs/basic_bugs.htm'):
        data += b'<a href="https://pages.uoregon.edu/koch/texshop/">TeXShop</a>'
    if args.mutation == 'macro' and path.name == 'Macros_Latex.plist':
        data = data.replace(b'open location "https://texshop.app/"', b'open location "https://pages.uoregon.edu/koch/texshop/texshop.html"')
    if args.mutation == 'source' and path.name == 'TSAppDelegate.m':
        data += b'\n// https://pages.uoregon.edu/koch/texshop/texshop-current.txt\n'
    return data.decode('latin-1')


problems = []
pdfs = 0
files = [p for d in ('Resources', 'Sources') for p in sorted((root/d).rglob('*')) if p.is_file()]
for path in files:
    rel = path.relative_to(root)
    if VENDORED in path.parents or path.suffix in INDEXES or path.name.endswith(' idx'):
        continue
    if path.suffix.lower() == '.pdf':
        pdfs += 1
        reader = PdfReader(path)
        for number, page in enumerate(reader.pages, 1):
            for annotation in page.get('/Annots') or []:
                uri = (annotation.get_object().get('/A') or {}).get('/URI')
                if uri and FORMER.search(str(uri)):
                    problems.append('%s page %d links to %s' % (rel, number, uri))
            if not history(path) and FORMER.search(page.extract_text() or ''):
                problems.append('%s page %d names the former web site' % (rel, number))
        continue
    text = text_of(path)
    for match in LINK.finditer(text):
        if path.suffix in ('.htm', '.html') and match.group(0).startswith('\\'):
            continue  # TeX source shown as text in a help page, not a link
        problems.append('%s links to the former web site: %s' % (rel, match.group(0)[:100]))
    if not history(path):
        for match in FORMER.finditer(text):
            problems.append('%s names the former web site: %s' % (rel, match.group(0)))

# The help sends bug reports to GitHub issues in every language.
issues = 'https://github.com/TeXShopProject/TeXShop/issues'
bug_pages = sorted((root/'Resources/Interfaces').glob('*.lproj/TeXShopHelp/pgs/basic_bugs.htm'))
assert len(bug_pages) == 5, bug_pages
for page in bug_pages:
    text = page.read_bytes().decode('latin-1')
    if args.mutation == 'bug-contact' and page.parent.parent.parent.name == 'de.lproj':
        text = text.replace(issues, 'https://example.org/')
    if ('href="%s"' % issues) not in text:
        problems.append('%s does not send bug reports to GitHub issues' % page.relative_to(root))

if problems:
    print('\n'.join('FAIL ' + p for p in problems))
    sys.exit('FAIL: %d places lead to the former web site' % len(problems))
print('PASS: %d files and %d PDFs lead nowhere on the former web site; bug reports go to GitHub issues in %d help languages'
      % (len(files) - pdfs, pdfs, len(bug_pages)))
