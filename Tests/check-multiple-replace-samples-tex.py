#!/usr/bin/env python3
"""The sample sets of multiple replacement, checked with TeX (not part of every test run; skipped without TeX Live).

1. Every character that "Unicode Characters → ajmacros" converts is put in a document twice on a line, in the middle
   and at the end (so that the % at the end of a line is typeset too). The sample is applied by the multiple
   replacement engine, and the result is typeset by upLaTeX with ujarticle, otf and ajmacros: no error and no
   warning, and no character missing from a font.
2. The PDF has, for each character, two glyphs whose CIDs (Identity-H, so the codes in the content streams) are the
   Adobe-Japan1 CID that Hiragino draws for the character, or a known variant that ajmacros uses.
3. "ajmacros → Unicode Characters" applied to the converted document gives back the document, except for the %
   that the first set adds at the end of a line (it is a TeX comment, which the reverse set keeps).

--tex DIR: the bin folder of TeX Live (default /Applications/TeXLive/2026/bin/universal-darwin).
--keep DIR: keep the documents, the log and the PDF there.
--mutations: check that the test fails when the PDF is missing, a glyph is wrong or extra, or a variant is not the known one."""
from pathlib import Path
import argparse
import collections
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
SAMPLES = root / 'Resources/MultipleReplaceSamples'
TO_MACROS = SAMPLES / 'UnicodeToAjmacros.json'
TO_CHARACTERS = SAMPLES / 'AjmacrosToUnicode.json'


def runner():
    sys.path.insert(0, str(root / 'Tests'))
    spec = importlib.util.spec_from_file_location('samples_runner', root / 'Tests/run-multiple-replace-samples.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def notes():
    """The kind of each character, from the notes of the sample."""
    kinds = {}
    for rule in json.loads(TO_MACROS.read_text())['replacements']:
        if not rule.get('usesRegularExpression'):
            kinds.setdefault(rule['findString'], rule['description'])
    return kinds


# The characters that ajmacros draws with another glyph of the same character than Hiragino's own (checked by eye,
# 2026-11-14): the negative squared letters, 令和 as Adobe-Japan1-7's square ligature, and variants of ℧ and €.
KNOWN_VARIANTS = {chr(0x1F170 + i): 11174 + i for i in range(26)} | {'\u32FF': 23058, '\u2127': 16204, '\u20AC': 9779}


# Each breaks one thing; the test must fail (--mutations).
MUTATIONS = {
    'no-pdf': 'the PDF is not made',
    'wrong-glyph': 'a character is typeset as another one',
    'extra-glyph': 'a line has one glyph more',
    'unknown-variant': 'a variant of ajmacros is not the known one',
}


def pdf_cids(path):
    """The CIDs of the glyphs of Identity-H (Type0) fonts, in the order of the content streams."""
    from pypdf import PdfReader
    from pypdf.generic import ContentStream
    reader = PdfReader(str(path))
    cids = []
    for page in reader.pages:
        fonts = page['/Resources'].get('/Font', {})
        stream = ContentStream(page.get_contents(), reader)
        current = None
        for operands, operator in stream.operations:
            if operator == b'Tf':
                font = fonts[operands[0]].get_object()
                current = font if font.get('/Subtype') == '/Type0' and font.get('/Encoding') in ('/Identity-H', '/Identity-V') else None
            elif operator in (b'Tj', b"'", b'"', b'TJ') and current is not None:
                items = operands[0] if operator == b'TJ' else [operands[-1]]
                for item in items:
                    if isinstance(item, (bytes, str)) or hasattr(item, 'original_bytes'):
                        data = item.original_bytes if hasattr(item, 'original_bytes') else bytes(item)
                        cids += [int.from_bytes(data[k:k + 2], 'big') for k in range(0, len(data) - 1, 2)]
    return cids


DOCUMENT = r'''\documentclass{ujarticle}
\usepackage[uplatex]{otf}
\usepackage{ajmacros}
\tracinglostchars=2
\begin{document}
%s
\end{document}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tex', type=Path, default=Path('/Applications/TeXLive/2026/bin/universal-darwin'))
    parser.add_argument('--keep', type=Path)
    parser.add_argument('--mutation', choices=sorted(MUTATIONS))
    parser.add_argument('--mutations', action='store_true', help='check that each mutation makes this test fail')
    args = parser.parse_args()
    if args.mutations:
        for name in sorted(MUTATIONS):
            result = subprocess.run([sys.executable, __file__, '--tex', str(args.tex), '--mutation', name], capture_output=True, text=True)
            if result.returncode == 0:
                sys.exit(f'FAIL: mutation {name!r} was not detected')
            print(f'PASS: detected mutation {name!r}')
        return
    mutation = args.mutation or ''
    uplatex, dvipdfmx = args.tex / 'uplatex', args.tex / 'dvipdfmx'
    if not uplatex.exists() or not dvipdfmx.exists():
        print(f'SKIP: no upLaTeX in {args.tex}')
        return
    module = runner()
    with tempfile.TemporaryDirectory(prefix='texshop-samples-tex-') as tmp:
        tmp = Path(tmp)
        probe = module.build(tmp, root / 'Sources/Find', root / 'Sources/Utilities')
        targets_file = tmp / 'targets.txt'
        subprocess.run([str(probe), 'targets', '-', str(targets_file)], check=True, capture_output=True)
        targets = targets_file.read_text().split('\n')
        kinds = notes()
        # One line for each character: in the middle of the line and at its end.
        body = ''.join(f'a{t}b {t}\n\\par\n' for t in targets)
        original = tmp / 'original.txt'
        original.write_text(body)
        converted = tmp / 'converted.txt'
        subprocess.run([str(probe), 'apply', str(TO_MACROS), str(original), str(converted)], check=True, capture_output=True)
        latex = converted.read_text()
        if mutation == 'wrong-glyph':
            latex = latex.replace('a\\ajMaru{1}b', 'a\\ajMaru{2}b', 1)
        elif mutation == 'extra-glyph':
            latex = latex.replace('a\\ajMaru{1}b', 'a\\ajMaru{1}\\ajMaru{1}b', 1)
        source = tmp / 'samples.tex'
        source.write_text(DOCUMENT % latex)
        result = subprocess.run([str(uplatex), '-interaction=nonstopmode', '-halt-on-error', 'samples.tex'], cwd=tmp,
                                capture_output=True, text=True, errors='replace')
        log = (tmp / 'samples.log').read_text(errors='replace') if (tmp / 'samples.log').exists() else result.stdout
        errors = [l for l in log.splitlines() if l.startswith('!')]
        warnings = [l for l in log.splitlines() if 'Warning' in l or 'Missing character' in l]
        failed = False
        report = {'characters': len(targets)}
        if result.returncode or errors:
            print(f'FAIL: upLaTeX stops: {errors[:5]}')
            failed = True
        if warnings:
            print(f'FAIL: {len(warnings)} warnings, such as {warnings[:5]}')
            failed = True
        if not failed:
            print(f'PASS: upLaTeX typesets the {len(targets)} characters converted by the sample, in the middle and at the end of lines, '
                  f'with no error, no warning and no missing character')
        subprocess.run([str(dvipdfmx), 'samples.dvi'], cwd=tmp, capture_output=True, check=not failed)
        if mutation == 'no-pdf':
            (tmp / 'samples.pdf').unlink()
        variants = dict(KNOWN_VARIANTS)
        if mutation == 'unknown-variant':
            variants['\u20AC'] = 9354

        # 2. The glyphs in the PDF. ajmacros draws the characters with Identity-H CID fonts, whose codes in the
        # content streams are the Adobe-Japan1 CIDs themselves: two glyphs per line (in the middle and at the end),
        # each the CID that Hiragino draws for the character, or the variant that ajmacros is known to use.
        cids_file = tmp / 'cids.txt'
        subprocess.run([str(probe), 'cids', str(targets_file), str(cids_file)], check=True, capture_output=True)
        expected = [int(c) for c in cids_file.read_text().split('\n')]
        pdf = tmp / 'samples.pdf'
        if not pdf.exists():
            print('FAIL: dvipdfmx made no PDF')
            failed = True
            glyphs = []
        else:
            glyphs = pdf_cids(pdf)
        mismatches, used = [], collections.Counter()
        if glyphs and len(glyphs) != 2 * len(targets):
            print(f'FAIL: the PDF has {len(glyphs)} glyphs of CID fonts, not {2 * len(targets)} (two for each of {len(targets)} characters)')
            failed = True
        elif glyphs:
            for i, t in enumerate(targets):
                kind = kinds.get(t, '?')
                for where, cid in (('middle', glyphs[2 * i]), ('end', glyphs[2 * i + 1])):
                    if t in variants:
                        ok = cid == variants[t]
                        used[kind] += ok and where == 'middle'
                    else:
                        ok = expected[i] != 0 and cid == expected[i]
                    if not ok:
                        mismatches.append(dict(kind=kind, character=t, where=where, pdf=cid, expected=variants.get(t, expected[i])))
            if mismatches:
                print(f'FAIL: {len(mismatches)} glyphs are not the CID of their character, such as {mismatches[:5]}')
                failed = True
            else:
                print(f'PASS: the PDF has, for each of the {len(targets)} characters, in the middle and at the end of its line, the '
                      f'Adobe-Japan1 CID of the character ({len(targets) - sum(used.values())} as Hiragino draws it, '
                      f'{sum(used.values())} as the known variants of ajmacros)')
        report['pdf'] = dict(glyphs=len(glyphs), mismatches=mismatches, variants=dict(used))

        # 3. The reverse set gives the document back, but for the % at the ends of lines.
        back = tmp / 'back.txt'
        subprocess.run([str(probe), 'apply', str(TO_CHARACTERS), str(converted), str(back)], check=True, capture_output=True)
        lines, again = body.split('\n'), back.read_text().split('\n')
        differ = [(o, b) for o, b in zip(lines, again) if o != b and not (b.endswith('%') and b[:-1] == o)]
        with_percent = sum(1 for o, b in zip(lines, again) if o != b and b.endswith('%') and b[:-1] == o)
        if len(lines) != len(again) or differ:
            print(f'FAIL: the reverse set does not give the document back: {differ[:5]}')
            failed = True
        else:
            print(f'PASS: the reverse set gives the document back; {with_percent} lines keep the % that the first set adds at their end')
        report.update(errors=errors, warnings=warnings, reverse_differs=[list(d) for d in differ], reverse_percent=with_percent)
        if args.keep:
            args.keep.mkdir(parents=True, exist_ok=True)
            (args.keep / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=1))
            for name in ['cids.txt', 'original.txt', 'converted.txt', 'back.txt', 'samples.tex', 'samples.log', 'samples.pdf']:
                if (tmp / name).exists():
                    shutil.copy(tmp / name, args.keep / name)
        if failed:
            sys.exit('FAIL: the samples checked with TeX')
    print('PASS: the samples checked with TeX')


if __name__ == '__main__':
    main()
