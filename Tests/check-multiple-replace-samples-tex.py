#!/usr/bin/env python3
"""The sample sets of multiple replacement, checked with TeX (not part of every test run; skipped without TeX Live).

1. Every character that "Unicode Characters → ajmacros" converts is put in a document twice on a line, in the middle
   and at the end (so that the % at the end of a line is typeset too). The sample is applied by the multiple
   replacement engine, and the result is typeset by upLaTeX with ujarticle, otf and ajmacros: no error and no
   warning, and no character missing from a font.
2. The text of the PDF is read back: for each kind, how many of its characters come back as they were.
3. "ajmacros → Unicode Characters" applied to the converted document gives back the document, except for the %
   that the first set adds at the end of a line (it is a TeX comment, which the reverse set keeps).

--tex DIR: the bin folder of TeX Live (default /Applications/TeXLive/2026/bin/universal-darwin).
--keep DIR: keep the documents, the log and the PDF there."""
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
TO_MACROS = SAMPLES / 'Unicode Characters → ajmacros.json'
TO_CHARACTERS = SAMPLES / 'ajmacros → Unicode Characters.json'


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
    args = parser.parse_args()
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

        # 2. The text of the PDF. ajmacros draws most characters by \CID, whose text in the PDF is the CID itself
        # (no ToUnicode): a character comes back when the PDF has it, or its Adobe-Japan1 CID, on its line.
        cids_file = tmp / 'cids.txt'
        subprocess.run([str(probe), 'cids', str(targets_file), str(cids_file)], check=True, capture_output=True)
        cids = [int(c) for c in cids_file.read_text().split('\n')]
        recovered, as_cid, totals = collections.Counter(), collections.Counter(), collections.Counter()
        other = []
        if (tmp / 'samples.pdf').exists():
            from pypdf import PdfReader
            text = '\n'.join(page.extract_text() or '' for page in PdfReader(str(tmp / 'samples.pdf')).pages)
            rows = [l for l in text.split('\n') if l.startswith('a ') or l.startswith('a')]
            for i, t in enumerate(targets):
                kind = kinds.get(t, '?')
                totals[kind] += 1
                row = rows[i] if i < len(rows) else ''
                # "a X b X": the glyph between a and b.
                middle = row[1:row.index('b')].strip() if 'b' in row[1:] else ''
                if middle == t or middle == t.replace(' ', ''):
                    recovered[kind] += 1
                elif len(middle) == 1 and cids[i] and ord(middle) == cids[i]:
                    as_cid[kind] += 1
                elif middle == '' and cids[i] and chr(cids[i]).isspace():
                    # CIDs 8192–8202 and 8287 read as the spaces U+2000–U+200A and U+205F, which the text drops.
                    as_cid[kind] += 1
                else:
                    other.append((kind, t, middle, cids[i]))
            print('Text of the PDF, for each kind: the character itself / its Adobe-Japan1 CID / something else:')
            for kind in dict.fromkeys(kinds.get(t, '?') for t in targets):
                print(f'  {kind}: {recovered[kind]} / {as_cid[kind]} / {totals[kind] - recovered[kind] - as_cid[kind]}')
            # Known: ajmacros draws these with other glyphs of the same character than Hiragino's own (checked by eye,
            # 2026-11-14): 🅰–🆉 at CIDs 11174–11199, ㋿ at 23058 (Adobe-Japan1-7's 令和), ℧ and € at other variants.
            for kind, t, middle, cid in other:
                print(f'  else: {kind} {t} (U+{ord(t[0]):04X}, CID {cid}) → {middle!r} ({", ".join(f"U+{ord(c):04X}" for c in middle)})')
            report['pdf'] = {'itself': sum(recovered.values()), 'cid': sum(as_cid.values()),
                             'other': [dict(kind=k, character=t, pdf=m, cid=c) for k, t, m, c in other]}

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
