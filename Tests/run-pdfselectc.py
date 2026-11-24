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
fill the page.

Pages whose crop box goes past the media box show only the part inside it (ISO 32000-1, 14.11.2). The source and the
new pages are drawn by Ghostscript at 72 dpi (4 dpi for the large pages) and must have the same size and each of four
colored rectangles in the same place, give or take a pixel: a crop box partly outside (the audit's case) with Rotate
0/90/180/270, with and without UserUnit; one outside on all four sides; one inside; one equal to the media box; one
inherited from the page tree; a page too large for points that keeps its UserUnit; one whose crop box is too large for
TeX, so that the media box is placed; and one where both are, so that the page keeps its UserUnit.

Each mutation (a copy of the script with one change) must be caught: ignore-userunit reads every UserUnit as 1;
place-page-size squeezes the whole crop box onto the page (the bug of the second audit); place-mediabox gives luatex the
media box but places it as the crop box; turn-margins mixes up Rotate 90 and 270 when the box is moved. --mutation NAME
runs the whole test against that copy and fails.
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
MUTATIONS = {'ignore-userunit': ('local unit = pdfe.getnumber(page, "UserUnit")', 'local unit = 1'),
             'place-page-size': ('across * try, up * try, left * try, bottom * try}', 'width * try, height * try, 0, 0}'),
             'place-mediabox': ('{{"cropbox", crop}, {"mediabox", media}}', '{{"mediabox", crop}, {"mediabox", media}}'),
             'turn-margins': ('if rotate == 90 then left, bottom', 'if rotate == 270 then left, bottom')}
GS = None
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

# Four rectangles, each its own color, in fractions of an anchor box (the media box unless a page names another): red and
# green inside, blue over the lower left corner and yellow over the upper right one, both partly outside the media box.
COLORS = {'red': (0.8, 0.2, 0.1), 'green': (0.3, 0.6, 0.1), 'blue': (0.1, 0.2, 0.8), 'yellow': (0.9, 0.8, 0.1)}
SHAPES = [('red', 0.1, 0.08, 0.5, 0.72), ('green', 0.25, 0.26, 0.625, 0.66), ('blue', -0.15, -0.15, 0.2, 0.15),
          ('yellow', 0.7, 0.85, 1.15, 1.15)]


def drawing(anchor):
    x0, y0, x1, y1 = anchor
    w, h = x1 - x0, y1 - y0
    parts = ['q']
    for color, a, b, c, d in SHAPES:
        r, g, bl = COLORS[color]
        parts.append(f'{r} {g} {bl} rg {x0 + a * w:g} {y0 + b * h:g} {(c - a) * w:g} {(d - b) * h:g} re f')
    parts.append('Q')
    return ' '.join(parts)


def write_pdf(path, pages, tree=''):
    """A PDF 1.7 file written by hand: each page a dict with media, and crop, unit, rotate and anchor when it has them;
    tree is put into the page tree (to be inherited)."""
    body = {1: b'<< /Type /Catalog /Pages 2 0 R >>'}
    kids = []
    for i, page in enumerate(pages):
        number, content = 3 + 2 * i, 4 + 2 * i
        kids.append(f'{number} 0 R')
        entry = f'<< /Type /Page /Parent 2 0 R /MediaBox [{" ".join(map(str, page["media"]))}]'
        if page.get('crop'):
            entry += f' /CropBox [{" ".join(map(str, page["crop"]))}]'
        if page.get('unit'):
            entry += f' /UserUnit {page["unit"]}'
        if page.get('rotate'):
            entry += f' /Rotate {page["rotate"]}'
        body[number] = (entry + f' /Resources << >> /Contents {content} 0 R >>').encode()
        stream = drawing(page.get('anchor', page['media'])).encode()
        body[content] = b'<< /Length %d >>\nstream\n' % len(stream) + stream + b'\nendstream'
    body[2] = f'<< /Type /Pages /Kids [{" ".join(kids)}] /Count {len(pages)} {tree}>>'.encode()
    out = bytearray(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
    offsets = {}
    for key in sorted(body):
        offsets[key] = len(out)
        out += b'%d 0 obj\n' % key + body[key] + b'\nendobj\n'
    start = len(out)
    out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(body) + 1)
    for key in sorted(body):
        out += b'%010d 00000 n \n' % offsets[key]
    out += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(body) + 1, start)
    path.write_bytes(bytes(out))


MEDIA = [0, 0, 200, 250]
PARTIAL = [-20, -30, 160, 230]  # the audit's crop box: past the media box on the left and at the bottom
AROUND = [-20, -30, 240, 300]  # past the media box on all four sides, by 20, 30, 40 and 50
CROP_FILES = {
    # name: (pages, page tree, dpi)
    'crops': ([dict(media=MEDIA, crop=PARTIAL, rotate=r, unit=u) for u in (None, 2.5) for r in (0, 90, 180, 270)] +
              [dict(media=MEDIA, crop=AROUND, rotate=r, unit=2) for r in (0, 90, 180, 270)] +
              [dict(media=MEDIA, crop=[20, 30, 160, 230]), dict(media=MEDIA, crop=[20, 30, 160, 230], rotate=270, unit=2.5),
               dict(media=MEDIA, crop=MEDIA), dict(media=MEDIA, crop=MEDIA, rotate=90, unit=2.5),
               # Crop and media box both too large for TeX at UserUnit 2.5: the page keeps its unit.
               dict(media=[0, 0, 7000, 7000], crop=[-7000, -7000, 100, 100], unit=2.5, rotate=90, anchor=[-20, -20, 120, 120])],
              '', 72),
    'inherit': ([dict(media=MEDIA, rotate=90, unit=2.5), dict(media=MEDIA)], f'/CropBox [{" ".join(map(str, PARTIAL))}] ', 72),
    'large': ([dict(media=[0, 0, 10000, 6000], crop=[-100, -50, 9000, 6000], unit=2, rotate=90),
               # The crop box is too large for TeX at UserUnit 50, the media box is not.
               dict(media=MEDIA, crop=[-200, -200, 400, 450], unit=50, rotate=180)], '', 4),
}
# The UserUnit of the new pages; None for pages made in points.
CROP_UNITS = {'crops': [None] * 12 + [None] * 4 + [2.5], 'inherit': [None, None], 'large': [2, None]}


def render(pdf, dpi, top):
    """Each page of pdf drawn by Ghostscript (the crop box inside the media box, with UserUnit): a list of
    (width, height, rows of RGB bytes)."""
    folder = Path(tempfile.mkdtemp(prefix='render-', dir=top))
    env = {'PATH': os.environ['PATH'], 'HOME': os.environ.get('HOME', '/'), 'TMPDIR': str(folder) + '/'}
    subprocess.run([GS, '-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-dUseCropBox', '-sDEVICE=ppmraw', f'-r{dpi}',
                    f'-sOutputFile={folder}/page-%03d.ppm', str(pdf)], env=env, check=True, capture_output=True, timeout=120)
    images = []
    for name in sorted(p.name for p in folder.glob('page-*.ppm')):
        data = (folder / name).read_bytes()
        fields, at = [], 0
        while len(fields) < 4:
            while data[at:at + 1].isspace():
                at += 1
            if data[at:at + 1] == b'#':
                at = data.index(b'\n', at)
                continue
            end = at
            while not data[end:end + 1].isspace():
                end += 1
            fields.append(data[at:end])
            at = end
        width, height = int(fields[1]), int(fields[2])
        pixels = data[at + 1:]
        images.append((width, height, [pixels[y * width * 3:(y + 1) * width * 3] for y in range(height)]))
    shutil.rmtree(folder)
    return images


def color_boxes(image):
    """The pixel box of each of the four colors: {color: (left, top, right, bottom)}."""
    width, height, rows = image
    targets = {name: tuple(round(v * 255) for v in rgb) for name, rgb in COLORS.items()}
    boxes = {}
    white = b'\xff' * (width * 3)
    for y, row in enumerate(rows):
        if row == white:
            continue
        for x in range(width):
            pixel = row[3 * x:3 * x + 3]
            if pixel == b'\xff\xff\xff':
                continue
            for name, (r, g, b) in targets.items():
                if abs(pixel[0] - r) + abs(pixel[1] - g) + abs(pixel[2] - b) < 40:
                    box = boxes.get(name)
                    boxes[name] = (x, y, x, y) if box is None else (min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y))
                    break
    return boxes


def crop_checks(scripts, folder, tmp, top):
    """Failures of the crop box cases run with the scripts in the folder scripts."""
    found = []
    def expect(ok, message):
        if not ok:
            found.append(message)
    for name, (pages, tree, dpi) in CROP_FILES.items():
        source = folder / f'{name}.pdf'
        if not source.exists():
            write_pdf(source, pages, tree)
        made = folder / f'{name}-1.pdf'
        made.unlink(missing_ok=True)
        result = run([f'1:{len(pages)}', name], folder, tmp, scripts)
        expect(result.returncode == 0, f'{name}: pdfselectc succeeds: {result.returncode} {result.stderr}')
        if not made.exists():
            expect(False, f'{name}-1.pdf is made')
            continue
        _, before = info(source, top)
        _, after = info(made, top)
        expect(len(after) == len(pages), f'{name}-1.pdf has {len(pages)} pages: {len(after)}')
        for number, (old, new, unit) in enumerate(zip(before, after, CROP_UNITS[name]), 1):
            where = f'{name}-1.pdf, page {number}'
            expect(near(old['shown'], new['shown']), f'{where} is shown at {new["shown"]} points, not {old["shown"]}')
            expect(new['unit'] == unit and new['rotate'] == 0, f'{where} has UserUnit {new["unit"]} and Rotate {new["rotate"]}')
        wanted, got = render(source, dpi, top), render(made, dpi, top)
        expect(len(wanted) == len(got), f'{name}: Ghostscript draws {len(got)} pages, not {len(wanted)}')
        for number, (a, b) in enumerate(zip(wanted, got), 1):
            where = f'{name}-1.pdf, page {number} at {dpi} dpi'
            if abs(a[0] - b[0]) > 1 or abs(a[1] - b[1]) > 1:
                expect(False, f'{where} is {b[0]}x{b[1]} pixels, not {a[0]}x{a[1]}')
                continue
            boxes_a, boxes_b = color_boxes(a), color_boxes(b)
            expect(len(boxes_a) >= 2, f'{name}.pdf, page {number}: the test draws at least two colors: {boxes_a}')
            for color in COLORS:
                one, two = boxes_a.get(color), boxes_b.get(color)
                expect((one is None) == (two is None) and (one is None or all(abs(p - q) <= 1 for p, q in zip(one, two))),
                       f'{where}: {color} lies at {two}, not {one}')
        made.unlink()
    expect(not any(tmp.iterdir()), f'the temporary folder is removed after the crop box cases: {list(tmp.iterdir())}')
    return found


def pages(pdf):
    return int(subprocess.run(['qpdf', '--show-npages', str(pdf)], capture_output=True, text=True, check=True).stdout)


def main(mutation=None):
    if TEXBIN is None:
        print('FAIL: TeX Live with texlua and luatex is not found')
        sys.exit(1)
    global GS
    if shutil.which('qpdf') is None or shutil.which('gs') is None:
        os.environ['PATH'] += ':/usr/local/tetex/bin'
    GS = shutil.which('gs')
    if GS is None:
        print('FAIL: Ghostscript (gs) is not found')
        sys.exit(1)
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
            if item.get('name') == 'Extract Pages from PDF…':
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
        failures.extend(userunit_checks(scripts, folder, tmp, top))
        failures.extend(crop_checks(scripts, folder, tmp, top))
        if not mutation:
            # The test catches each mutated copy of pdfselectc.
            for name in MUTATIONS:
                copy = mutated(name, top)
                caught = userunit_checks(copy, folder, tmp, top) + crop_checks(copy, folder, tmp, top)
                check(bool(caught), f'mutation {name} is caught')

    if failures:
        print('\n'.join('FAIL: ' + f for f in failures))
        sys.exit(1)
    print('PASS: pdfselectc makes 3 selections of a 3-page PDF with texlua and luatex (page counts by qpdf, sizes by pdfe, crop box '
          'and /Rotate kept), 10 wrong uses stop with a message and no file, no temporary folder is left, pages with UserUnit '
          '(rotated, cropped, too large for points, 1, and none under a page tree with one) keep the size a viewer shows with '
          'content filling the page, pages whose crop box goes past the media box (Rotate 0/90/180/270, with and without '
          'UserUnit, inherited, too large) draw as the source in Ghostscript, and 4 mutated copies are caught')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=sorted(MUTATIONS), help='run the whole test against a mutated copy (it must fail)')
    main(parser.parse_args().mutation)
