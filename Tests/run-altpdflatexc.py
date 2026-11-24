#!/usr/bin/env python3
"""Macros › Claus Gerhardt Macros › Run LaTeX, dvips and ps2pdf makes the PDF with TeX Live and Ghostscript.

The macro calls ~/Library/TeXShop/bin/altpdflatexc, which called altpdflatex, a script TeX Live does not have. It now runs
latex, dvips and ps2pdf itself. In a private folder whose name has a space, a quote and a dollar sign, the shell command
the macro builds (cd to the folder, then altpdflatexc with the quoted file name) is run on a small LaTeX file whose name
has a space: it must make "<name>.pdf" (the name as before), one page, with Type 1 fonts (dvips -Poutline), and leave
nothing in TMPDIR. When latex stops with an error, when dvips fails (a missing header file) and when ps2pdf fails (bad
PostScript), it must stop with exit status 1 and a message naming the step on standard error, and an earlier PDF must
be left as it was. Only a DVI file made by this run may go on to dvips: when the body is emptied after a good run
("No pages of output", latex exits 0) and when latex stops with an error (an undefined command, a missing \\input file),
the script must stop with exit status 1 without running dvips, the earlier PDF must be left byte for byte, and the
earlier DVI file must be put back. The macro must still call the script as before.

Mutated copies of the script (MUTATIONS) must each fail the test; --mutation NAME runs the whole test against one.

TeX Live 2026 and Ghostscript are put in PATH (the script also adds the paths set in TeXShop's Settings).
"""
from pathlib import Path
import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'Resources/TeXShop/bin/altpdflatexc'
TEXBIN = next((d for d in ['/Applications/TeXLive/2026/bin/universal-darwin', '/Library/TeX/texbin']
               if Path(d, 'latex').exists() and Path(d, 'dvips').exists()), None)
GSBIN = next((d for d in ['/usr/local/teTeX/bin', '/usr/local/tetex/bin', '/usr/local/bin', '/opt/homebrew/bin', '/opt/local/bin']
              if Path(d, 'gs').exists() and Path(d, 'ps2pdf').exists()), None)
GOOD = r'''\documentclass{article}
\begin{document}
Hello, \textbf{world} and $x^2 + \sqrt{y}$.
\end{document}
'''
MUTATIONS = {
    # dvips takes the DVI file the earlier run left (the bug found in the third audit)
    'stale-dvi': ('if [ -e "$name.dvi" ]; then\n'
                  '    /bin/mv -f "$name.dvi" "$work/earlier.dvi" || fail "cannot move the earlier $name.dvi aside"\n'
                  'fi\n', ''),
    # the earlier DVI file is lost when this run makes none
    'no-put-back': ('[ ! -e "$name.dvi" ] && [ -e "$work/earlier.dvi" ] && /bin/mv -f "$work/earlier.dvi" "$name.dvi"', ':'),
}
failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def mutated(name, top):
    old, new = MUTATIONS[name]
    text = SCRIPT.read_text()
    if text.count(old) != 1:
        sys.exit(f'mutation {name} does not apply once to altpdflatexc')
    copy = top / f'bin-{name}' / 'altpdflatexc'
    copy.parent.mkdir()
    copy.write_text(text.replace(old, new))
    shutil.copymode(SCRIPT, copy)
    return copy


def quoted_form(text):
    """AppleScript's quoted form of."""
    return "'" + text.replace("'", "'\\''") + "'"


def run_macro_command(script, folder, tex, tmp):
    # As the macro builds it: "cd " & dirName & ";" & "~/Library/TeXShop/bin/altpdflatexc  " & quoted form of baseName
    command = 'cd ' + quoted_form(str(folder)) + ';' + quoted_form(str(script)) + '  ' + quoted_form(tex)
    env = {'PATH': f'{TEXBIN}:{GSBIN}:/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': os.environ.get('HOME', str(tmp)),
           'TMPDIR': str(tmp) + '/', 'CFFIXED_USER_HOME': os.environ.get('CFFIXED_USER_HOME', str(tmp))}
    return subprocess.run(['/bin/sh', '-c', command], env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL,
                          timeout=300)


def pdf_facts(pdf):
    """(page count, font subtypes) of a PDF, read with pypdf when it is there, else by the bytes."""
    if not pdf.exists():
        return 0, set()
    data = pdf.read_bytes()
    if not data.startswith(b'%PDF-'):
        return 0, set()
    try:
        from pypdf import PdfReader
        reader = PdfReader(str(pdf))
        subtypes = set()
        for page in reader.pages:
            fonts = page.get('/Resources', {}).get('/Font', {})
            for font in fonts.values():
                subtypes.add(str(font.get_object().get('/Subtype')))
        return len(reader.pages), subtypes
    except ImportError:
        return data.count(b'/Type /Page\n') or data.count(b'/Type/Page'), set(re.findall(rb'/Subtype\s*/(Type1C?|Type3|TrueType)', data))


def macro_checks():
    macros = plistlib.loads((ROOT / 'Resources/TeXShop/Macros/Macros_Latex.plist').read_bytes())
    found = []

    def walk(items):
        for item in items:
            if 'submenu' in item:
                walk(item['submenu'])
            elif item.get('name') == 'Run LaTeX, dvips and ps2pdf':
                found.append(item.get('content', ''))
    walk(macros.get('submenu', []))
    check(len(found) == 1, f'one Run LaTeX, dvips and ps2pdf macro: {len(found)}')
    if found:
        check('set shellScript to shellScript & "~/Library/TeXShop/bin/altpdflatexc  " & quoted form of baseName' in found[0],
              'the macro calls ~/Library/TeXShop/bin/altpdflatexc with the quoted file name')
    text = SCRIPT.read_text()
    check(os.access(SCRIPT, os.X_OK), 'altpdflatexc is executable')
    commands = [line for line in text.splitlines() if not line.lstrip().startswith('#')]
    check(not any(re.search(r'\baltpdflatex\b', line) for line in commands), 'altpdflatexc no longer calls altpdflatex')


def script_checks(script, top):
    """Runs the script through the macro's command; the failures go to the global list."""
    tmp = top / 'tmp'
    tmp.mkdir(parents=True)
    folder = top / 'my "doc" $HOME'
    folder.mkdir()
    tex = 'a b.tex'
    pdf = folder / 'a b.pdf'
    dvi = folder / 'a b.dvi'
    (folder / tex).write_text(GOOD)
    result = run_macro_command(script, folder, tex, tmp)
    check(result.returncode == 0, f'the good file is made: {result.returncode} {result.stderr[-500:]}')
    check(pdf.exists(), 'a b.pdf is made (the name as before)')
    if pdf.exists():
        pages, fonts = pdf_facts(pdf)
        check(pages == 1, f'one page: {pages}')
        check(fonts and fonts <= {'/Type1', '/Type1C', b'Type1', b'Type1C'}, f'Type 1 fonts only: {fonts}')
    check(not (folder / 'a b.ps').exists(), 'no PostScript file is left beside the document')
    check(not list(folder.glob('a b.pdf.*')), 'no partial PDF is left')
    check(not any(tmp.iterdir()), f'nothing is left in TMPDIR: {list(tmp.iterdir())}')
    check(dvi.exists(), 'the good run leaves a b.dvi beside the document (the reruns below need it)')
    good_pdf = pdf.read_bytes() if pdf.exists() else b''
    good_dvi = dvi.read_bytes() if dvi.exists() else b''

    # Reruns in which latex makes no new DVI file: the earlier a b.dvi must not reach dvips.
    reruns = [('empty body', r'\documentclass{article}\begin{document}\end{document}' + '\n', 'latex made no a b.dvi'),
              ('undefined command', r'\documentclass{article}\begin{document}\undefinedcommand\end{document}' + '\n',
               'latex stopped with an error'),
              ('missing input file', r'\documentclass{article}\begin{document}x\input{no-such-file}\end{document}' + '\n',
               'latex stopped with an error')]
    for label, source, message in reruns:
        (folder / tex).write_text(source)
        result = run_macro_command(script, folder, tex, tmp)
        check(result.returncode == 1, f'{label}: stops with 1: {result.returncode} {result.stderr[-300:]!r}')
        check(result.stderr.startswith('altpdflatexc: ' + message), f'{label}: says "{message}": {result.stderr[:300]!r}')
        check('### dvips' not in result.stdout, f'{label}: dvips is not run')
        check('is made' not in result.stdout, f'{label}: does not say the PDF is made')
        check(pdf.read_bytes() == good_pdf, f'{label}: the earlier PDF is left byte for byte')
        check(dvi.exists() and dvi.read_bytes() == good_dvi, f'{label}: the earlier a b.dvi is put back')
        check(not any(tmp.iterdir()), f'{label}: nothing is left in TMPDIR: {list(tmp.iterdir())}')
        if label == 'empty body':
            # The case only means something when latex itself exits 0 with no pages.
            log = (folder / 'a b.log').read_text(errors='replace')
            check('No pages of output' in log, f'{label}: latex says No pages of output')

    cases = [('latex', r'\documentclass{article}\begin{document}\undefinedcommand\end{document}' + '\n',
              'latex stopped with an error'),
             ('dvips', r'\documentclass{article}\special{header=no-such-header-file.pro}\begin{document}x\end{document}' + '\n',
              'dvips could not make'),
             ('ps2pdf', r'\documentclass{article}\begin{document}x\special{ps: 1 0 div}\end{document}' + '\n',
              'ps2pdf could not make')]
    for step, source, message in cases:
        (folder / tex).write_text(source)
        result = run_macro_command(script, folder, tex, tmp)
        check(result.returncode == 1, f'{step} failure stops with 1: {result.returncode}')
        check(result.stderr.startswith('altpdflatexc: ' + message), f'{step} failure says "{message}": {result.stderr[:300]!r}')
        check(pdf.read_bytes() == good_pdf, f'{step} failure leaves the earlier PDF as it was')
        check(not any(tmp.iterdir()), f'{step} failure leaves nothing in TMPDIR: {list(tmp.iterdir())}')

    # After the failures, the good source makes the PDF again.
    (folder / tex).write_text(GOOD)
    result = run_macro_command(script, folder, tex, tmp)
    check(result.returncode == 0 and pdf_facts(pdf)[0] == 1, f'the good file is made again: {result.returncode}')


def main(mutation):
    global failures
    if TEXBIN is None or GSBIN is None:
        sys.exit(f'FAIL: TeX Live ({TEXBIN}) and Ghostscript ({GSBIN}) are needed')
    with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as top:
        top = Path(top)
        if mutation:
            script_checks(mutated(mutation, top), top / 'run')
        else:
            macro_checks()
            script_checks(SCRIPT, top / 'run')
            for name in MUTATIONS:
                kept, failures = failures, []
                script_checks(mutated(name, top), top / f'run-{name}')
                caught, failures = failures, kept
                check(caught, f'mutation {name} is caught')
    if failures:
        print('\n'.join('FAIL: ' + f for f in failures))
        sys.exit(1)
    print('PASS: Run LaTeX, dvips and ps2pdf makes "a b.pdf" (one page, Type 1 fonts) in a folder with a space, a quote and $ '
          'with TeX Live and Ghostscript, leaves no temporary file, and stops with a message and the earlier PDF kept when '
          'latex, dvips or ps2pdf fails; reruns with an empty body, an undefined command and a missing input file stop with '
          'status 1 without passing the earlier DVI to dvips, keep the earlier PDF byte for byte and put the earlier DVI back; '
          f'the macro calls the script as before; {len(MUTATIONS)} mutated copies are caught')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=sorted(MUTATIONS), help='run the whole test against a mutated copy (it must fail)')
    main(parser.parse_args().mutation)
