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
earlier DVI file must be put back. This holds also when latex writes a page to the DVI file before it stops (a missing
\\input file after \\newpage): the partial DVI file must not take the place of the earlier one, and with no earlier DVI
file no DVI file may be left. When dvips or ps2pdf fails, the earlier DVI file is put back too. A folder (with a file in
it) named "<name>.dvi", "<name>.ps" or "<name>.pdf", and a link named "<name>.dvi", must stop the script before latex
with a message and a status other than 0, and be left as they were. The macro must still call the script as before.

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
# One page goes to the DVI file, then latex stops on the missing file (fatal in nonstop mode).
PARTIAL = (r'\documentclass{article}\begin{document}PARTIAL PAGE\newpage' + '\n'
           r'\input{no-such-file}\end{document}' + '\n')
MUTATIONS = {
    # The copy before the PDF is put in place goes to a fixed name of the PDF and a number,
    # which writes over a file of the user's of that name.
    'fixed-temporary-name': [('pdf_tmp=$(/usr/bin/mktemp "./.$name.pdf.XXXXXX") || fail "cannot write $name.pdf"\n',
                              'pdf_tmp="$n.pdf.4242"\n')],
    # The copy keeps the owner-only permissions of mktemp.
    'owner-only-pdf': [('/bin/chmod "$(printf \'%o\' $((0666 & ~0$(umask))))" "$pdf_tmp" || fail "cannot write $name.pdf"\n', '')],
    # dvips takes the DVI file the earlier run left (the bug found in the third audit)
    'stale-dvi': [('if [ -f "$n.dvi" ]; then\n'
                   '    /bin/mv -f "$n.dvi" "$work/earlier.dvi" || fail "cannot move the earlier $name.dvi aside"\n'
                   'fi\n', '')],
    # the earlier DVI file is lost when this run makes none
    'no-put-back': [('[ -n "$made" ] || put_back_dvi', ':')],
    # the earlier DVI file is put back only when latex wrote none (the bug found in the fourth audit)
    'restore-only-when-empty': [('        /bin/mv -f "$work/earlier.dvi" "$n.dvi" ||',
                                 '        [ -e "$n.dvi" ] || /bin/mv -f "$work/earlier.dvi" "$n.dvi" ||')],
    # whatever is at the DVI path is moved aside, a folder too (the other bug found in the fourth audit)
    'move-directory': [('if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then', 'if false; then'),
                       ('if [ -f "$n.dvi" ]; then\n    /bin/mv -f "$n.dvi"', 'if [ -e "$n.dvi" ]; then\n    /bin/mv -f "$n.dvi"')],
}
failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def mutated(name, top):
    text = SCRIPT.read_text()
    for old, new in MUTATIONS[name]:
        if text.count(old) != 1:
            sys.exit(f'mutation {name} does not apply once to altpdflatexc: {old!r}')
        text = text.replace(old, new)
    copy = top / f'bin-{name}' / 'altpdflatexc'
    copy.parent.mkdir()
    copy.write_text(text)
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
    check(pdf.exists() and (pdf.stat().st_mode & 0o777) == 0o644, f'a b.pdf has the permissions of a new file: {oct(pdf.stat().st_mode & 0o777) if pdf.exists() else None}')
    check(not list(folder.glob('.a b.pdf.*')), 'no temporary copy of the PDF is left beside it')
    # A file of the user's whose name looks like the old temporary copy (the PDF's name and a
    # number) is never written over or removed by a run.
    bystander = folder / 'a b.pdf.4242'
    bystander.write_text('keep me')
    rerun = run_macro_command(script, folder, tex, tmp)
    check(rerun.returncode == 0, f'a second good run works: {rerun.stderr[-300:]}')
    check(bystander.exists() and bystander.read_text() == 'keep me', 'a b.pdf.4242 of the user is left as it was')
    bystander.unlink(missing_ok=True)
    check(not list(folder.glob('.a b.pdf.*')), 'no temporary copy is left after the second run')
    good_pdf = pdf.read_bytes() if pdf.exists() else b''
    good_dvi = dvi.read_bytes() if dvi.exists() else b''

    # A name that starts with - is not read as an option by basename, mv, rm or the TeX programs.
    dash = top / 'dash'
    dash.mkdir()
    (dash / '-x.tex').write_text(GOOD)
    result = run_macro_command(script, dash, '-x.tex', tmp)
    check(result.returncode == 0 and (dash / '-x.pdf').exists(),
          f'a document named -x.tex makes -x.pdf: {result.returncode} {result.stderr[-300:]}')

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
        check(dvi.exists() and dvi.read_bytes() == good_dvi, f'{step} failure puts the earlier a b.dvi back')
        check(not any(tmp.iterdir()), f'{step} failure leaves nothing in TMPDIR: {list(tmp.iterdir())}')

    # latex writes one page to the DVI file, then stops on a missing \input file (the fourth audit): the earlier
    # DVI file must come back in place of the partial one; with no earlier DVI file, none may be left.
    (folder / tex).write_text(PARTIAL)
    for earlier in (True, False):
        label = 'partial output ' + ('after a good run' if earlier else 'with no earlier DVI')
        if not earlier and dvi.exists():
            dvi.unlink()
        result = run_macro_command(script, folder, tex, tmp)
        log = (folder / 'a b.log').read_text(errors='replace')
        check('Output written on "a b.dvi" (1 page' in log, f'{label}: latex writes one page before it stops (the case is real)')
        check(result.returncode == 1, f'{label}: stops with 1: {result.returncode} {result.stderr[-300:]!r}')
        check(result.stderr.startswith('altpdflatexc: latex stopped with an error'), f'{label}: says latex stopped: {result.stderr[:300]!r}')
        check('### dvips' not in result.stdout, f'{label}: dvips is not run')
        check(pdf.read_bytes() == good_pdf, f'{label}: the earlier PDF is left byte for byte')
        if earlier:
            check(dvi.exists() and dvi.read_bytes() == good_dvi, f'{label}: the earlier a b.dvi is put back byte for byte')
        else:
            check(not dvi.exists(), f'{label}: no partial a b.dvi is left')
        check(not any(tmp.iterdir()), f'{label}: nothing is left in TMPDIR: {list(tmp.iterdir())}')

    # After the failures, the good source makes the PDF again.
    (folder / tex).write_text(GOOD)
    result = run_macro_command(script, folder, tex, tmp)
    check(result.returncode == 0 and pdf_facts(pdf)[0] == 1, f'the good file is made again: {result.returncode}')
    check(dvi.exists() and dvi.read_bytes() != b'', 'the good run keeps its new a b.dvi')

    # A folder or a link at the DVI, PostScript or PDF path stops the script before latex; nothing there is touched.
    guard = top / 'guard "x" $HOME'
    guard.mkdir()
    (guard / tex).write_text(GOOD)
    for ext, kind in [('dvi', 'folder'), ('ps', 'folder'), ('pdf', 'folder'), ('dvi', 'link')]:
        label = f'a {kind} named a b.{ext}'
        item = guard / f'a b.{ext}'
        target = guard / 'target.bin'
        if kind == 'folder':
            item.mkdir()
            (item / 'inside.txt').write_bytes(b'keep me\n')
        else:
            target.write_bytes(b'not a DVI file\n')
            item.symlink_to(target.name)
        result = run_macro_command(script, guard, tex, tmp)
        check(result.returncode != 0, f'{label}: stops with a status other than 0: {result.returncode}')
        check(result.stderr.startswith(f'altpdflatexc: a b.{ext} is a folder, a link'), f'{label}: says why: {result.stderr[:300]!r}')
        check('### latex' not in result.stdout and not (guard / 'a b.log').exists(), f'{label}: latex is not run')
        if kind == 'folder':
            check(item.is_dir() and not item.is_symlink() and sorted(x.name for x in item.iterdir()) == ['inside.txt']
                  and (item / 'inside.txt').read_bytes() == b'keep me\n', f'{label}: the folder and its file are left as they were')
        else:
            check(item.is_symlink() and os.readlink(item) == target.name and target.read_bytes() == b'not a DVI file\n',
                  f'{label}: the link and the file it points to are left as they were')
        check(sorted(x.name for x in guard.iterdir()) == sorted([tex, item.name] + ([target.name] if kind == 'link' else [])),
              f'{label}: nothing else is made beside the document: {sorted(x.name for x in guard.iterdir())}')
        check(not any(tmp.iterdir()), f'{label}: nothing is left in TMPDIR: {list(tmp.iterdir())}')
        # A mutated script may have left anything here; clear the folder for the next case.
        for x in guard.iterdir():
            if x.name != tex:
                shutil.rmtree(x) if x.is_dir() and not x.is_symlink() else x.unlink()


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
          'a run that writes one page and then stops puts the earlier DVI back over the partial one, or leaves no DVI '
          'when there was none; a folder named .dvi, .ps or .pdf and a link named .dvi stop the script and are left as '
          f'they were; the macro calls the script as before; {len(MUTATIONS)} mutated copies are caught')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=sorted(MUTATIONS), help='run the whole test against a mutated copy (it must fail)')
    main(parser.parse_args().mutation)
