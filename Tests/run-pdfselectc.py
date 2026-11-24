#!/usr/bin/env python3
"""pdfselectc (Macros › Claus Gerhardt Macros) makes PDF files of selected pages with texlua and luatex of TeX Live.

A 3-page PDF with pages of different sizes, one with a crop box and one turned by /Rotate 90, is made with plain
luatex in a private folder whose name has a space and a quote. pdfselectc then makes three selections from it, and the
pages and sizes of the results are read with qpdf and with pdfe. Wrong selections, a missing file, a file that is not a
PDF and one that needs a password stop at once with exit status 1, a message and no file; nothing is left in TMPDIR.
The macro still calls the script as before: the selections, then the file name without .pdf.

Pages with /UserUnit (PDF 1.6; the length of the page's unit in points, not inherited) keep the size a viewer shows:
UserUnit 2 with /Rotate 90 or 270, 2.5 with a crop box, a page too large for 14400 points that keeps its own UserUnit,
UserUnit 1, and a page with no UserUnit under a page tree that has one. The content of each new page is checked to
fill the page. The mutation ignore-userunit (a copy of the script that reads every UserUnit as 1) must be caught;
--mutation ignore-userunit runs the whole test against that copy and fails.
"""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'Resources/TeXShop/bin'
MUTATIONS = {'ignore-userunit': ('local unit = pdfe.getnumber(page, "UserUnit")', 'local unit = 1')}
TEXBIN = next((d for d in ['/Applications/TeXLive/2026/bin/universal-darwin', '/Library/TeX/texbin']
               if Path(d, 'texlua').exists() and Path(d, 'luatex').exists()), None)
failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def environment(tmp):
    env = {'PATH': f'{TEXBIN}:/usr/bin:/bin', 'HOME': os.environ.get('HOME', '/'), 'TMPDIR': str(tmp) + '/',
           'CFFIXED_USER_HOME': os.environ.get('CFFIXED_USER_HOME', str(tmp))}
    return env


def run(args, folder, tmp, scripts=BIN):
    return subprocess.run([str(scripts / 'pdfselectc'), *args], cwd=folder, env=environment(tmp), capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=120)


def mutated(name, top):
    """A copy of pdfselectc and pdfselectc.lua with one mutation."""
    old, new = MUTATIONS[name]
    folder = top / f'bin-{name}'
    folder.mkdir()
    shutil.copy2(BIN / 'pdfselectc', folder / 'pdfselectc')
    script = (BIN / 'pdfselectc.lua').read_text()
    check(script.count(old) == 1, f'mutation {name} applies to pdfselectc.lua')
    (folder / 'pdfselectc.lua').write_text(script.replace(old, new))
    return folder


# Each page: the PDF version, then the media box, UserUnit (- when missing), Rotate, crop box and, when the page draws one
# form with "a b c d e f cm /Name Do", where the form's BBox lands on the page (its corners through Matrix and cm).
INFO = r'''
local d = pdfe.open(arg[1])
local major, minor = pdfe.getversion(d)
print(string.format("version %d.%d", major, minor))
for i = 1, pdfe.getnofpages(d) do
  local p = pdfe.getpage(d, i)
  local m = pdfe.getbox(p, "MediaBox")
  local c = pdfe.getbox(p, "CropBox") or m
  local u = pdfe.getnumber(p, "UserUnit")
  local placed = "-"
  local stream = pdfe.getstream(p, "Contents")
  local content = stream and pdfe.readwholestream(stream, true) or ""
  local n = {}
  local name
  n[1], n[2], n[3], n[4], n[5], n[6], name = content:match(
    "([-%d.]+)%s+([-%d.]+)%s+([-%d.]+)%s+([-%d.]+)%s+([-%d.]+)%s+([-%d.]+)%s+cm%s*/(%S+)%s+Do")
  local resources = pdfe.getdictionary(p, "Resources")
  local forms = resources and pdfe.getdictionary(resources, "XObject")
  if name and forms then
    local _, form = pdfe.getstream(forms, name)
    local b = form and pdfe.getbox(form, "BBox")
    if b then
      local f = form and pdfe.getarray(form, "Matrix")
      local fm = {1, 0, 0, 1, 0, 0}
      if f then for k = 1, 6 do fm[k] = pdfe.getnumber(f, k - 1) end end
      local cm = {}
      for k = 1, 6 do cm[k] = tonumber(n[k]) end
      local xs, ys = {}, {}
      for _, corner in ipairs({{b[1], b[2]}, {b[1], b[4]}, {b[3], b[2]}, {b[3], b[4]}}) do
        local x, y = corner[1], corner[2]
        x, y = fm[1] * x + fm[3] * y + fm[5], fm[2] * x + fm[4] * y + fm[6]
        x, y = cm[1] * x + cm[3] * y + cm[5], cm[2] * x + cm[4] * y + cm[6]
        xs[#xs + 1], ys[#ys + 1] = x, y
      end
      placed = string.format("%g %g %g %g", math.min(table.unpack(xs)), math.min(table.unpack(ys)),
                             math.max(table.unpack(xs)), math.max(table.unpack(ys)))
    end
  end
  print(string.format("%g %g %g %g | %s | %d | %g %g %g %g | %s", m[1], m[2], m[3], m[4], u and string.format("%g", u) or "-",
                      pdfe.getinteger(p, "Rotate") or 0, c[1], c[2], c[3], c[4], placed))
end
'''


def info(pdf, work):
    """The version of the PDF and, for each page, a dict of its boxes, UserUnit, Rotate and shown size in points."""
    script = work / 'info.lua'
    script.write_text(INFO)
    out = subprocess.run([f'{TEXBIN}/texlua', str(script), str(pdf)], capture_output=True, text=True, check=True, timeout=60).stdout
    lines = out.splitlines()
    version = lines[0].split()[1]
    result = []
    for line in lines[1:]:
        media, unit, rotate, crop, placed = [part.strip() for part in line.split('|')]
        media = [float(v) for v in media.split()]
        crop = [float(v) for v in crop.split()]
        unit = None if unit == '-' else float(unit)
        rotate = int(rotate) % 360
        box = [max(min(crop[0], crop[2]), min(media[0], media[2])), max(min(crop[1], crop[3]), min(media[1], media[3])),
               min(max(crop[0], crop[2]), max(media[0], media[2])), min(max(crop[1], crop[3]), max(media[1], media[3]))]
        shown = [(box[2] - box[0]) * (unit or 1), (box[3] - box[1]) * (unit or 1)]
        if rotate in (90, 270):
            shown.reverse()
        result.append({'media': (media[2] - media[0], media[3] - media[1]), 'mediabox': media, 'unit': unit, 'rotate': rotate,
                       'shown': tuple(shown), 'placed': None if placed == '-' else [float(v) for v in placed.split()]})
    return version, result


def sizes(pdf, work):
    return [page['media'] for page in info(pdf, work)[1]]


def near(a, b):
    return len(a) == len(b) and all(abs(x - y) < 0.01 for x, y in zip(a, b))


UNITS = r'''\outputmode=1
\pdfvariable horigin=0pt \pdfvariable vorigin=0pt
\pdfvariable minorversion=7
\pdfvariable pagesattr{/UserUnit 3}
\parindent=0pt \nopagenumbers
\def\pg#1#2#3{\pagewidth=#1bp \pageheight=#2bp \hsize=#1bp \vsize=#2bp
  \vbox to #2bp{\vss\hbox{\hskip10bp Page #3}\vskip10bp}\par\vfill\penalty-10000 }
\pdfvariable pageattr{/UserUnit 2 /Rotate 90}
\pg{200}{300}{one}
\pdfvariable pageattr{/UserUnit 2}
\pg{200}{300}{two}
\pdfvariable pageattr{/UserUnit 2.5 /CropBox [20 30 120 230]}
\pg{200}{300}{three}
\pdfvariable pageattr{/UserUnit 2}
\pg{10000}{6000}{four}
\pdfvariable pageattr{/UserUnit 2 /Rotate 270}
\pg{6000}{10000}{five}
\pdfvariable pageattr{/UserUnit 1}
\pg{200}{300}{six}
\pdfvariable pageattr{}
\pg{200}{300}{seven}
\bye
'''
# Shown size in points of each page of units.pdf, and the UserUnit of the new page: 1 (no entry) unless the page is larger
# than 14400 points, when it keeps its own unit. Page 7 has no UserUnit; the 3 of the page tree is not inherited.
UNIT_PAGES = {1: ((600, 400), None), 2: ((400, 600), None), 3: ((250, 500), None), 4: ((20000, 12000), 2),
              5: ((20000, 12000), 2), 6: ((200, 300), None), 7: ((200, 300), None)}


def userunit_checks(scripts, folder, tmp, top):
    """Failures of the UserUnit cases run with the scripts in the folder scripts; units.pdf and units15.pdf are made in folder."""
    found = []
    def expect(ok, message):
        if not ok:
            found.append(message)
    for pdf in folder.glob('units*-*.pdf'):
        pdf.unlink()
    version, source = info(folder / 'units.pdf', top)
    expect(version == '1.7' and [(p['shown'], p['unit'], p['rotate']) for p in source] ==
           [((600, 400), 2, 90), ((400, 600), 2, 0), ((250, 500), 2.5, 0), ((20000, 12000), 2, 0), ((20000, 12000), 2, 270),
            ((200, 300), 1, 0), ((200, 300), None, 0)],
           f'units.pdf as made: {version} {[(p["shown"], p["unit"], p["rotate"]) for p in source]}')
    selections = {1: [1], 2: [2], 3: [3, 6, 7], 4: [4, 5, 1], 5: [6], 6: [7]}
    result = run([','.join(map(str, pages)) for pages in selections.values()] + ['units'], folder, tmp, scripts)
    expect(result.returncode == 0, f'UserUnit selections succeed: {result.returncode} {result.stderr}')
    for index, pages in selections.items():
        pdf = folder / f'units-{index}.pdf'
        if not pdf.exists():
            expect(False, f'units-{index}.pdf is made')
            continue
        version, got = info(pdf, top)
        expect(version == '1.7', f'units-{index}.pdf keeps PDF 1.7: {version}')
        expect(len(got) == len(pages), f'units-{index}.pdf has {len(pages)} pages: {len(got)}')
        for number, page in zip(pages, got):
            shown, unit = UNIT_PAGES[number]
            where = f'units-{index}.pdf, page {number} of units.pdf'
            expect(near(page['shown'], shown), f'{where} is shown at {page["shown"]} points, not {shown}')
            expect(page['unit'] == unit, f'{where} has UserUnit {page["unit"]}, not {unit}')
            expect(page['rotate'] == 0, f'{where} has Rotate {page["rotate"]}')
            expect(page['placed'] is not None and near(page['placed'], page['mediabox']),
                   f'{where}: the content lands on {page["placed"]}, not the page {page["mediabox"]}')
    # The page with UserUnit 1 is made exactly as the same page without UserUnit (page 7 under the page tree's UserUnit 3).
    if (folder / 'units-5.pdf').exists() and (folder / 'units-6.pdf').exists():
        one, none = info(folder / 'units-5.pdf', top)[1], info(folder / 'units-6.pdf', top)[1]
        expect(one == none and near(one[0]['mediabox'], [0, 0, 200, 300]), f'UserUnit 1 changes nothing: {one} {none}')
    # A PDF 1.5 file with a page that keeps its UserUnit becomes PDF 1.6, where UserUnit begins.
    result = run(['1', 'units15'], folder, tmp, scripts)
    expect(result.returncode == 0, f'units15 succeeds: {result.returncode} {result.stderr}')
    if (folder / 'units15-1.pdf').exists():
        version, got = info(folder / 'units15-1.pdf', top)
        expect(version == '1.6' and len(got) == 1 and got[0]['unit'] == 2 and near(got[0]['shown'], (30000, 20000)),
               f'units15-1.pdf: {version} {got}')
    expect(not any(tmp.iterdir()), f'the temporary folder is removed after the UserUnit cases: {list(tmp.iterdir())}')
    for pdf in folder.glob('units*-*.pdf'):
        pdf.unlink()
    return found


def pages(pdf):
    return int(subprocess.run(['qpdf', '--show-npages', str(pdf)], capture_output=True, text=True, check=True).stdout)


def main(mutation=None):
    if TEXBIN is None:
        print('FAIL: TeX Live with texlua and luatex is not found')
        sys.exit(1)
    if shutil.which('qpdf') is None:
        os.environ['PATH'] += ':/usr/local/tetex/bin'
    # The script runs with only TeX Live and /bin/sh: no ConTeXt MkII, Ruby, Python or Perl.
    wrapper = (BIN / 'pdfselectc').read_text()
    script = (BIN / 'pdfselectc.lua').read_text()
    check(wrapper.startswith('#!/bin/sh\n') and os.access(BIN / 'pdfselectc', os.X_OK), 'pdfselectc is an executable /bin/sh script')
    check('exec texlua "$(dirname "$0")/pdfselectc.lua" "$@"' in wrapper, 'pdfselectc runs pdfselectc.lua with texlua')
    for word in ('texexec', 'ruby', 'python', 'perl', 'context', 'mtxrun'):
        check(word not in (wrapper + script).lower(), f'pdfselectc does not use {word}')
    check('pdfe.open' in script and 'pdfe.getnofpages' in script and 'pdfe.getbox' in script, 'pages are read with pdfe')
    # The macro: the selections, then the name without .pdf, in the document's folder.
    with open(ROOT / 'Resources/TeXShop/Macros/Macros_Latex.plist', 'rb') as f:
        macros = plistlib.load(f)
    found = []
    def walk(items):
        for item in items:
            if item.get('name') == 'pdfselectc':
                found.append(item['content'])
            walk(item.get('submenu', []))
    walk(macros.get('submenu', []))
    check(len(found) == 1, 'one pdfselectc macro')
    if found:
        check('"~/Library/TeXShop/bin/pdfselectc  " & input' in found[0] and 'set input to input & " " & baseName' in found[0],
              'the macro passes the selections and then the file name')

    with tempfile.TemporaryDirectory(prefix='texshop-pdfselectc-') as top:
        top = Path(top)
        tmp = top / 'tmp'
        tmp.mkdir()
        folder = top / "Mike's papers"
        folder.mkdir()
        scripts = mutated(mutation, top) if mutation else BIN
        (folder / 'three.tex').write_text(r'''\outputmode=1
\pdfvariable horigin=0pt \pdfvariable vorigin=0pt
\parindent=0pt \nopagenumbers
\def\pg#1#2#3{\pagewidth=#1bp \pageheight=#2bp \hsize=#1bp \vsize=#2bp
  \vbox to #2bp{\vss\hbox{\hskip10bp Page #3}\vskip10bp}\par\vfill\penalty-10000 }
\pg{200}{300}{one}
\pdfvariable pageattr{/CropBox [50 25 350 225]}
\pg{400}{250}{two}
\pdfvariable pageattr{/Rotate 90}
\pg{300}{320}{three}
\bye
''')
        subprocess.run([f'{TEXBIN}/luatex', '-interaction=batchmode', 'three.tex'], cwd=folder, env=environment(tmp),
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True, timeout=120)
        source = folder / 'three.pdf'
        check(pages(source) == 3, 'the test PDF has 3 pages')
        check(sizes(source, top) == [(200, 300), (400, 250), (300, 320)], f'media boxes of the test PDF: {sizes(source, top)}')

        result = run(['3:3,1', '2', '1:3,2', 'three'], folder, tmp, scripts)
        check(result.returncode == 0, f'three selections succeed: {result.returncode} {result.stderr}')
        # Page 2 is its crop box (300 x 200); page 3 is turned (320 x 300).
        expected = {1: [(320, 300), (200, 300)], 2: [(300, 200)], 3: [(200, 300), (300, 200), (320, 300), (300, 200)]}
        for index, wanted in expected.items():
            pdf = folder / f'three-{index}.pdf'
            check(pdf.exists(), f'three-{index}.pdf is made')
            if pdf.exists():
                check(pages(pdf) == len(wanted), f'three-{index}.pdf has {len(wanted)} pages (qpdf: {pages(pdf)})')
                got = sizes(pdf, top)
                check(len(got) == len(wanted) and all(abs(a - c) < 0.01 and abs(b - d) < 0.01 for (a, b), (c, d) in zip(got, wanted)),
                      f'three-{index}.pdf page sizes {got}, not {wanted}')
                check(all(page['unit'] is None for page in info(pdf, top)[1]), f'three-{index}.pdf has no UserUnit')
        check(sorted(p.name for p in folder.iterdir()) == ['three-1.pdf', 'three-2.pdf', 'three-3.pdf', 'three.log', 'three.pdf', 'three.tex'],
              f'nothing else is left in the folder: {sorted(p.name for p in folder.iterdir())}')
        check(not any(tmp.iterdir()), f'the temporary folder is removed: {list(tmp.iterdir())}')
        for pdf in folder.glob('three-*.pdf'):
            pdf.unlink()

        (folder / 'junk.pdf').write_text('not a PDF\n')
        subprocess.run(['qpdf', '--encrypt', 'user', 'owner', '256', '--', str(source), str(folder / 'locked.pdf')], check=True)
        errors = [(['1:5', 'three'], 'has pages 1 to 3 only'), (['0', 'three'], 'has pages 1 to 3 only'),
                  (['3:1', 'three'], 'goes backwards'), (['2,a', 'three'], 'is not a page or a range'),
                  (['1,,2', 'three'], 'is not a page or a range'), (['1', '2:9', 'three'], 'selection 2 (2:9)'),
                  (['1', 'missing'], 'cannot find missing.pdf'), (['1', 'junk'], 'is not a PDF file'),
                  (['1', 'locked'], 'protected by a password'), (['three'], 'usage: pdfselectc')]
        for args, message in errors:
            try:
                result = run(args, folder, tmp, scripts)
            except subprocess.TimeoutExpired:
                check(False, f'{args} does not finish (the former texexec waited for ever)')
                continue
            check(result.returncode != 0, f'{args} fails: {result.returncode}')
            check(message in result.stderr, f'{args} says "{message}": {result.stderr!r}')
            check(not list(folder.glob('three-*.pdf')) and not list(folder.glob('*-1.pdf')), f'{args} makes no file')
        check(not any(tmp.iterdir()), f'the temporary folder is removed after errors: {list(tmp.iterdir())}')

        (folder / 'units.tex').write_text(UNITS)
        # units15.pdf: PDF 1.5 with one page of 15000 x 10000 at UserUnit 2, too large for points.
        (folder / 'units15.tex').write_text(UNITS.split('\\pdfvariable pageattr')[0].replace('minorversion=7', 'minorversion=5') +
                                            '\\pdfvariable pageattr{/UserUnit 2}\n\\pg{15000}{10000}{one}\n\\bye\n')
        for name in ('units', 'units15'):
            subprocess.run([f'{TEXBIN}/luatex', '-interaction=batchmode', f'{name}.tex'], cwd=folder, env=environment(tmp),
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True, timeout=120)
        found = userunit_checks(scripts, folder, tmp, top)
        failures.extend(found)
        if not mutation:
            # The test catches a pdfselectc that ignores UserUnit.
            for name in MUTATIONS:
                caught = userunit_checks(mutated(name, top), folder, tmp, top)
                check(bool(caught), f'mutation {name} is caught')

    if failures:
        print('\n'.join('FAIL: ' + f for f in failures))
        sys.exit(1)
    print('PASS: pdfselectc makes 3 selections of a 3-page PDF with texlua and luatex (page counts by qpdf, sizes by pdfe, crop box '
          'and /Rotate kept), 10 wrong uses stop with a message and no file, no temporary folder is left, pages with UserUnit '
          '(rotated, cropped, too large for points, 1, and none under a page tree with one) keep the size a viewer shows with '
          'content filling the page, and a copy that ignores UserUnit is caught')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=sorted(MUTATIONS), help='run the whole test against a mutated copy (it must fail)')
    main(parser.parse_args().mutation)
