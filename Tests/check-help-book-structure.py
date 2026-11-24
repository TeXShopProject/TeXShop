#!/usr/bin/env python3
"""The help books share one page structure, one page set and working links.

Every page of the help books (English, Japanese, German, Spanish, Korean, French, Italian,
Dutch, Portuguese, Portuguese (Portugal), Romanian and Simplified Chinese) is HTML5 in
UTF-8 with the language of its book (<html lang>, see HTML_LANG), uses the shared header, side menu and content area,
and names no file that does not exist (links, images, anchors). The side menus match the
chapter contents pages (Scripts/update-help-navigation.py --check). Each translated book
has the pages of the English book: the Japanese book has its own pages on pTeX and
encodings instead of the English page on Japan, the Spanish book has a page on its
translation, and only the English book has the release notes (whatisnew.htm), to which
the other books link. Every page is listed in a chapter or is one of credits, hlpIndex
and whatisnew. No page of a translated book has the content area of the English page, that is, every
page is translated (the books of fr, it, nl, pt, pt-PT, ro and zh_CN fail here until they are).
Reads the help files only.
With --mutation NAME the check runs on a mutated copy and must fail; --mutations runs them all.
"""
from pathlib import Path
import re
import subprocess
import sys
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / 'Resources/Interfaces'
LANGUAGES = ['en', 'ja', 'de', 'es', 'ko', 'fr', 'it', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
# The <html lang> of each book: the .lproj name, as a BCP 47 tag where the two differ (pt.lproj is
# Brazilian Portuguese, zh_CN.lproj Simplified Chinese).
HTML_LANG = {'pt': ('pt-BR', 'pt'), 'zh_CN': ('zh-Hans', 'zh-CN')}
CHAPTERS = ['basic', 'advanced', 'configure', 'macros']
UNLISTED = {'credits.htm', 'hlpIndex.htm', 'whatisnew.htm'}
OWN = {'ja': ({'basic_j_ptex.htm', 'basic_j_encoding.htm'}, {'advanced_Japan.htm'}),
       'es': ({'basic_thistranslation.htm'}, set())}
OLD = re.compile(r'id="(?:header_background|header_logo|header_title|menu_border|content_border|content_normal)"'
                 r'|xicnsc\.gif|scB\.jpg|scic\.gif|header_background\.jpg|charset=iso-8859-1', re.I)
MUTATIONS = {
    # A page in Latin-1 again.
    'latin1': lambda files: files.__setitem__(
        ('de', 'pgs/basic_printing.htm'),
        files[('de', 'pgs/basic_printing.htm')].replace('<meta charset="utf-8">', '<meta http-equiv="content-type" content="text/html;charset=iso-8859-1">')),
    # A side menu that no longer matches its contents page.
    'stale-menu': lambda files: files.__setitem__(
        ('en', 'pgs/basic_printing.htm'), re.sub(r'<li><a href="basic_license.htm">.*?</li>\n', '', files[('en', 'pgs/basic_printing.htm')])),
    # A link to a page that is gone.
    'broken-link': lambda files: files.__setitem__(
        ('ko', 'pgs/basic.htm'), files[('ko', 'pgs/basic.htm')].replace('</ul>', '<li><a href="basic_missing.htm">x</a></li>\n</ul>', 1)),
    # A translated book misses a page of the English book.
    'missing-page': lambda files: files.pop(('es', 'pgs/basic_printing.htm')),
    # A Japanese page with the English text in its content area.
    'untranslated': lambda files: files.__setitem__(
        ('ja', 'pgs/basic_printing.htm'), re.sub(r'<main id="content".*?</main>', lambda m: content(files[('en', 'pgs/basic_printing.htm')]) or '',
                                                files[('ja', 'pgs/basic_printing.htm')], count=1, flags=re.S)),
    # A link to an anchor that no page defines.
    'broken-anchor': lambda files: files.__setitem__(
        ('ja', 'pgs/basic.htm'), files[('ja', 'pgs/basic.htm')].replace('href="basic_printing.htm"', 'href="basic_printing.htm#nowhere"', 1)),
}


def content(text):
    match = re.search(r'<main id="content".*?</main>', text, re.S)
    return match.group(0) if match else None


def strict_utf8(path):
    try:
        path.read_bytes().decode('utf-8')
        return True
    except UnicodeDecodeError:
        return False


def anchors(text):
    return set(re.findall(r'\b(?:id|name)="([^"]+)"', text))


def check(files, menus_current):
    failures = []
    pages = {language: {name for (lang, name) in files if lang == language and name.startswith('pgs/')} for language in LANGUAGES}
    for (language, name), text in sorted(files.items()):
        where = f'{language}.lproj/TeXShopHelp/{name}'
        if OLD.search(text):
            failures.append(f'{where}: old markup or image: {OLD.search(text).group(0)}')
        if not text.startswith('<!DOCTYPE html>'):
            failures.append(f'{where}: does not start with <!DOCTYPE html>')
        if '<meta charset="utf-8">' not in text:
            failures.append(f'{where}: does not declare UTF-8')
        langs = HTML_LANG.get(language, (language,))
        if not any(f'<html lang="{lang}">' in text for lang in langs):
            failures.append(f'{where}: <html lang> is not {" or ".join(langs)}')
        if name.startswith('pgs/') and name != 'pgs/whatisnew.htm':
            for part in ('<header id="header">', '<main id="content"'):
                if part not in text:
                    failures.append(f'{where}: no {part}')
            if name[4:].split('_')[0].split('.')[0] in CHAPTERS and '<nav id="menu">' not in text:
                failures.append(f'{where}: no side menu')
        folder = Path(name).parent
        for target in re.findall(r'\b(?:href|src)="([^"]+)"', text) + re.findall(r'name="AppleIcon" content="TeXShopHelp/([^"]+)"', text):
            if re.match(r'[a-z]+:', target) or target.startswith('#') and target[1:] in anchors(text):
                continue
            path, _, fragment = urllib.parse.unquote(target).partition('#')
            if not path:
                failures.append(f'{where}: link to missing anchor {target}')
                continue
            resolved = (Path(f'{language}.lproj/TeXShopHelp') / folder / path)
            parts = []
            for part in resolved.parts:
                if part == '..':
                    if parts:
                        parts.pop()
                elif part != '.':
                    parts.append(part)
            resolved = Path(*parts)
            match = re.match(r'([a-z_A-Z-]+)\.lproj/TeXShopHelp/(.*)', resolved.as_posix())
            if match and (match.group(1), match.group(2)) in files:
                if fragment and fragment not in anchors(files[(match.group(1), match.group(2))]):
                    failures.append(f'{where}: link to missing anchor {target}')
            elif not (INTERFACES / resolved).exists() or match and match.group(2).endswith(('.htm', '.html')):
                failures.append(f'{where}: link to missing file {target}')
    english = pages['en'] - {'pgs/whatisnew.htm'}
    for language in LANGUAGES[1:]:
        extra, missing = OWN.get(language, (set(), set()))
        expected = (english - {f'pgs/{p}' for p in missing}) | {f'pgs/{p}' for p in extra}
        for page in sorted(expected - pages[language]):
            failures.append(f'{language}: no {page} (the English book has it)')
        for page in sorted(pages[language] - expected):
            failures.append(f'{language}: {page} is not a page of the English book')
    for (language, name), text in sorted(files.items()):
        if language == 'en' or not name.startswith('pgs/'):
            continue
        mine, english = content(text), content(files.get(('en', name), ''))
        if mine is not None and english is not None and re.sub(r'\s+', ' ', mine) == re.sub(r'\s+', ' ', english):
            failures.append(f'{language}.lproj/TeXShopHelp/{name}: the content area is the English text')
    for language in LANGUAGES:
        listed = set()
        for chapter in CHAPTERS:
            text = files.get((language, f'pgs/{chapter}.htm'), '')
            toc = re.search(r'<ul class="toc">(.*?)</ul>', text, re.S)
            if not toc:
                failures.append(f'{language}: pgs/{chapter}.htm has no <ul class="toc">')
                continue
            listed |= set(re.findall(r'href="([^"#]+)"', toc.group(1)))
            listed.add(f'{chapter}.htm')
        for page in sorted(pages[language]):
            if page[4:] not in listed and page[4:] not in UNLISTED:
                failures.append(f'{language}: {page} is in no chapter')
        for (lang, name), text in files.items():
            if lang != language or not name.startswith('pgs/') or name == 'pgs/whatisnew.htm':
                continue
            menu = re.search(r'<nav id="menu">(.*?)</nav>', text, re.S)
            if not menu:
                continue
            chapter = name[4:].split('_')[0].split('.')[0]
            toc = re.search(r'<ul class="toc">(.*?)</ul>', files.get((language, f'pgs/{chapter}.htm'), ''), re.S)
            if toc and re.findall(r'href="([^"]+)"', menu.group(1)) != re.findall(r'href="([^"]+)"', toc.group(1)):
                failures.append(f'{language}.lproj/TeXShopHelp/{name}: side menu differs from pgs/{chapter}.htm')
    if not menus_current:
        failures.append('Scripts/update-help-navigation.py --check reports pages out of date')
    return failures


def run(mutation=None):
    files = {}
    for language in LANGUAGES:
        book = INTERFACES / f'{language}.lproj/TeXShopHelp'
        for path in sorted(book.rglob('*.htm*')):
            key = (language, path.relative_to(book).as_posix())
            if not strict_utf8(path):
                files[key] = 'charset=iso-8859-1 ' + path.read_bytes().decode('latin-1')
            else:
                files[key] = path.read_text(encoding='utf-8')
    if mutation:
        MUTATIONS[mutation](files)
    menus_current = subprocess.run([sys.executable, str(ROOT / 'Scripts/update-help-navigation.py'), '--check'],
                                   capture_output=True).returncode == 0
    return check(files, menus_current)


def main():
    args = sys.argv[1:]
    if args == ['--mutations']:
        # A mutation must add a failure of its own, also while a book still waits for its translation.
        baseline = set(run())
        survived = []
        for name in MUTATIONS:
            if not set(run(name)) - baseline:
                survived.append(name)
            print(f'mutation {name}: {"survived" if name in survived else "caught"}')
        sys.exit(1 if survived else 0)
    mutation = args[1] if args[:1] == ['--mutation'] else None
    failures = run(mutation)
    for failure in failures:
        print(failure)
    if failures:
        sys.exit(1)
    print(f'{sum(1 for _ in INTERFACES.glob("*.lproj/TeXShopHelp/**/*.htm*"))} help files checked')


if __name__ == '__main__':
    main()
