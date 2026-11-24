#!/usr/bin/env python3
"""pdfselectc (Macros › Claus Gerhardt Macros) makes PDF files of selected pages with texlua and luatex of TeX Live.

A 3-page PDF with pages of different sizes, one with a crop box and one turned by /Rotate 90, is made with plain
luatex in a private folder whose name has a space and a quote. pdfselectc then makes three selections from it, and the
pages and sizes of the results are read with qpdf and with pdfe. Wrong selections, a missing file, a file that is not a
PDF and one that needs a password stop at once with exit status 1, a message and no file; nothing is left in TMPDIR.
The macro still calls the script as before: the selections, then the file name without .pdf.
"""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'Resources/TeXShop/bin'
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


def run(args, folder, tmp):
    return subprocess.run([str(BIN / 'pdfselectc'), *args], cwd=folder, env=environment(tmp), capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=120)


SIZES = r'''
local d = pdfe.open(arg[1])
for i = 1, pdfe.getnofpages(d) do
  local p = pdfe.getpage(d, i)
  local m = pdfe.getbox(p, "MediaBox")
  print(string.format("%g %g", m[3] - m[1], m[4] - m[2]))
end
'''


def sizes(pdf, work):
    script = work / 'sizes.lua'
    script.write_text(SIZES)
    out = subprocess.run([f'{TEXBIN}/texlua', str(script), str(pdf)], capture_output=True, text=True, check=True, timeout=60).stdout
    return [tuple(float(v) for v in line.split()) for line in out.splitlines()]


def pages(pdf):
    return int(subprocess.run(['qpdf', '--show-npages', str(pdf)], capture_output=True, text=True, check=True).stdout)


def main():
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

        result = run(['3:3,1', '2', '1:3,2', 'three'], folder, tmp)
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
                result = run(args, folder, tmp)
            except subprocess.TimeoutExpired:
                check(False, f'{args} does not finish (the former texexec waited for ever)')
                continue
            check(result.returncode != 0, f'{args} fails: {result.returncode}')
            check(message in result.stderr, f'{args} says "{message}": {result.stderr!r}')
            check(not list(folder.glob('three-*.pdf')) and not list(folder.glob('*-1.pdf')), f'{args} makes no file')
        check(not any(tmp.iterdir()), f'the temporary folder is removed after errors: {list(tmp.iterdir())}')

    if failures:
        print('\n'.join('FAIL: ' + f for f in failures))
        sys.exit(1)
    print('PASS: pdfselectc makes 3 selections of a 3-page PDF with texlua and luatex (page counts by qpdf, sizes by pdfe, crop box '
          'and /Rotate kept), 10 wrong uses stop with a message and no file, and no temporary folder is left')


if __name__ == '__main__':
    main()
