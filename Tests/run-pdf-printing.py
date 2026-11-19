#!/usr/bin/env python3
"""Print a PDF of mixed pages (/Rotate 90 and 270, landscape, smaller and larger than A4)
offscreen to PDF files, as a print from the Preview does, and check each printed page:
turned to suit the paper and fitted to it by default, as Preview prints; each choice of the
print panel section (Auto Rotate, Scale, Scale to Fit) changes the printed pages.
Pass --keep=DIR to keep the printed PDFs; --mutation=NAME (no-rotate, actual-size, first-page-rotation,
shared-info, document-print-info, failed-save, spool-after-save, empty-field, summary-kvo) to show the checks fail without each part.
No window, panel or printer is used: the operation saves its job to a file."""
from pathlib import Path
import os, subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
keep = next((Path(a.split('=', 1)[1]) for a in sys.argv[1:] if a.startswith('--keep=')), None)
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)

mm = 72 / 25.4
MIXED = [(174*mm, 247*mm, 0, 'P1'), (174*mm, 247*mm, 90, 'P2 Rotate 90'), (174*mm, 247*mm, 270, 'P3 Rotate 270'),
             (247*mm, 174*mm, 0, 'P4 landscape'), (100*mm, 140*mm, 0, 'P5 small'), (297*mm, 420*mm, 90, 'P6 A3 Rotate 90')]
# The first page decides the paper: lying because of its /Rotate.
ROTATED_FIRST = [(174*mm, 247*mm, 90, 'R1 Rotate 90'), (174*mm, 247*mm, 0, 'R2')]

def make_pdf(path, pages):
    objs = []
    def add(b): objs.append(b); return len(objs)
    font = add(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
    contents = []
    for w, h, r, label in pages:
        # Blue frame at the page edge, red arrow pointing to the page's top, green label.
        s = (f'0 0 1 RG 4 w 2 2 {w-4:.2f} {h-4:.2f} re S 1 0 0 rg {w/2:.2f} {h-20:.2f} m {w/2-15:.2f} {h-50:.2f} l '
             f'{w/2+15:.2f} {h-50:.2f} l f 0 0.6 0 rg BT /F1 18 Tf 20 {h-40:.2f} Td ({label}) Tj ET').encode()
        contents.append(add(b'<< /Length %d >>\nstream\n' % len(s) + s + b'\nendstream'))
    pages_id = len(objs) + len(pages) + 1
    kids = [add(f'<< /Type /Page /Parent {pages_id} 0 R /MediaBox [0 0 {w:.2f} {h:.2f}] /Rotate {r} /Contents {c} 0 R '
                f'/Resources << /Font << /F1 {font} 0 R >> >> >>'.encode()) for (w, h, r, _), c in zip(pages, contents)]
    assert add(('<< /Type /Pages /Count %d /Kids [%s] >>' % (len(kids), ' '.join(f'{k} 0 R' for k in kids))).encode()) == pages_id
    catalog = add(f'<< /Type /Catalog /Pages {pages_id} 0 R >>'.encode())
    out = bytearray(b'%PDF-1.4\n'); offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out)); out += b'%d 0 obj\n' % i + o + b'\nendobj\n'
    xref = len(out); out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1)
    for o in offsets: out += b'%010d 00000 n \n' % o
    out += b'trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objs) + 1, catalog, xref)
    path.write_bytes(out)

with tempfile.TemporaryDirectory(prefix='texshop-pdf-printing-') as td:
    t = Path(td); (t/'home/Library').mkdir(parents=True); (t/'tmp').mkdir(); (t/'out').mkdir()
    source = root/'Sources/Preview/TSPDFPrinting.m'
    if mutation:
        text = source.read_text()
        old, new = {'no-rotate': ('settings[TSPDFPrintAutoRotateKey] = @YES;', 'settings[TSPDFPrintAutoRotateKey] = @NO;'),
                    'actual-size': ('settings[TSPDFPrintScalingModeKey] = @(kPDFPrintPageScaleToFit);', 'settings[TSPDFPrintScalingModeKey] = @(kPDFPrintPageScaleNone);'),
                    'first-page-rotation': ('if ((first.rotation / 90) % 2)', 'if (0)'),
                    'shared-info': ('NSPrintInfo *printInfo = [documentPrintInfo copy];', 'NSPrintInfo *printInfo = documentPrintInfo;'),
                    'document-print-info': ('    objc_setAssociatedObject(document,', '    document.printInfo = [document.printInfo copy]; [document.printInfo.dictionary addEntriesFromDictionary:kept];\n    objc_setAssociatedObject(document,'),
                    'failed-save': ('    if (! savedAfter)\n        return YES;', '    return YES;'),
                    'spool-after-save': ('    if (savedBefore && ! savedAfter)\n        return NO;', ''),
                    'empty-field': ('if (sender.objectValue == nil || sender.integerValue < 1) {', 'if (0) {'),
                    'summary-kvo': ('+ (NSSet<NSString *> *)keyPathsForValuesAffectingLocalizedSummaryItems', '+ (NSSet<NSString *> *)unusedKeyPaths')}[mutation]
        assert old in text; source = t/'TSPDFPrinting.m'; source.write_text(text.replace(old, new))
    make_pdf(t/'mixed.pdf', MIXED); make_pdf(t/'rotated-first.pdf', ROTATED_FIRST)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit', *include_args(root), '-I', str(root/'Tests'),
                    str(root/'Tests/PDFPrinting.m'), str(source), '-o', str(t/'probe')], check=True)
    env = dict(os.environ, HOME=str(t/'home'), TMPDIR=str(t/'tmp') + '/', CFFIXED_USER_HOME=str(t/'home'))
    result = subprocess.run([str(t/'probe'), str(t/'mixed.pdf'), str(t/'out'), str(t/'rotated-first.pdf')], env=env, text=True, capture_output=True)
    lines = result.stdout.splitlines()
    print('%d checks passed' % sum(l.startswith('ok:') for l in lines))
    print(''.join(l + '\n' for l in lines if not l.startswith('ok:')), end='')
    if keep:
        import shutil; shutil.copytree(t/'out', keep, dirs_exist_ok=True); shutil.copy(t/'mixed.pdf', keep)
    if result.returncode:
        print(result.stderr[-2000:]); raise SystemExit(result.returncode)
