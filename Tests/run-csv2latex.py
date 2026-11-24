#!/usr/bin/env python3
"""csv2latex (used by Macros › Paste Spreadsheet Cells) gives the tables the former Ruby script gave, now with texlua.

Tests/Fixtures/csv2latex holds clipboard texts (*.in) and, for each table style the macro offers (cells, simple,
booktabs, longtable), with no style and with a style it does not know, the table the Ruby csv2latex of TeXShop 5.59 to
6.00 RC 2 wrote (*.<style>.out); "-" in place of a file means it wrote nothing and left the clipboard alone. The texts
have LF, CRLF, CR and mixed line ends, blank rows, empty and missing cells, & $ # %, other TeX characters, quotes,
commas, spaces, UTF-8, Shift JIS whose second byte is a backslash, and ISO Latin 1. The expected tables were made by
running the Ruby script under a locale in which the bytes are valid (--make-fixtures RUBY); under the empty locale of
an app, the Ruby script stopped on any byte that is not ASCII, which the new script does not do.

Each table is made twice: by csv2latex.lua alone from the text, and by csv2latex with stand-ins for pbpaste and pbcopy
(which must be called with LANG and LC_ALL en_US.UTF-8). csv2latex says "Ok. In clipboard"; with nothing to paste it
says nothing, does not call pbcopy and exits with 0. The macro still calls ~/Library/TeXShop/bin/csv2latex with the
style chosen from the four.

Each mutation (a copy of the script with one change) must be caught. --mutation NAME runs the whole test against
that copy and fails.
"""
from pathlib import Path
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'Resources/TeXShop/bin'
FIXTURES = ROOT / 'Tests/Fixtures/csv2latex'
STYLES = ['cells', 'simple', 'booktabs', 'longtable', None, 'tabularx']
RUBY_COMMIT = '104da860'   # the last commit with the Ruby csv2latex
MUTATIONS = {'keep-empty-cells': ('while #fields > 0 and fields[#fields] == "" do', 'while false do'),
             'escape-underscore': ('"([&$#%%])"', '"([&$#%%_])"'),
             'double-backslash': ('{{Continued\\\\ldots}} \\\\")', '{{Continued\\\\ldots}} \\\\\\\\")'),
             'header-for-any-style': ('if hstyle == "simple" or hstyle == "cells" then', 'if hstyle ~= "booktabs" and hstyle ~= "longtable" then'),
             'lf-only': ('string.gsub(string.gsub(text, "\\r\\n", "\\r"), "\\n", "\\r")', 'string.gsub(text, "\\n", "\\r")'),
             'copy-empty': ('[ -s "$table" ] || exit 0', ':')}
TEXBIN = next((d for d in ['/Applications/TeXLive/2026/bin/universal-darwin', '/Library/TeX/texbin']
               if Path(d, 'texlua').exists()), None)

# The clipboard texts: name, bytes, and the locale in which the Ruby script read them.
INPUTS = [
    ('lf', b'Name\tAge\tCity\nAlice\t30\tParis\nBob\t25\tBerlin\n', 'en_US.UTF-8'),
    ('crlf', b'Name\tAge\tCity\r\nAlice\t30\tParis\r\nBob\t25\tBerlin\r\n', 'en_US.UTF-8'),
    ('cr', b'Name\tAge\rAlice\t30\rBob\t25\r', 'en_US.UTF-8'),
    ('mixed-ends', b'a\tb\r\r\nc\td\n\re\tf\r\n\n', 'en_US.UTF-8'),
    ('no-final-end', b'x\ty\nz\tw', 'en_US.UTF-8'),
    ('special', b'Cost $\t50%\t#1 & #2\nA&B\t$x$\t%comment\n', 'en_US.UTF-8'),
    ('other-tex', b'a_b\t{c}\t\\d\t~e^f\n<g>\t|h|\t"i"\n', 'en_US.UTF-8'),
    ('empty-cells', b'\ta\t\tb\t\t\n\t\t\n1\t\t3\n\t\t\t4\n', 'en_US.UTF-8'),
    ('ragged', b'h1\th2\nonly\n1\t2\t3\t4\t5\n', 'en_US.UTF-8'),
    ('blank-rows', b'\n\nh1\th2\n\n1\t2\n\n\n', 'en_US.UTF-8'),
    ('one-cell', b'alone', 'en_US.UTF-8'),
    ('header-only', b'h1\th2\th3\n', 'en_US.UTF-8'),
    ('tabs-only', b'\t\t\n\t\n', 'en_US.UTF-8'),
    ('empty', b'', 'en_US.UTF-8'),
    ('ends-only', b'\n\r\n\r\r\n', 'en_US.UTF-8'),
    ('quoted', b'"Name"\t"Note"\n"Smith, J."\t"line one\nline two"\n"say ""hi"""\t\'single\'\n', 'en_US.UTF-8'),
    ('commas', b'a,b,c\n1,2,3\n"x,y",z\n', 'en_US.UTF-8'),
    ('spaces', b' a \t  b\t c  \n   \t\t \n', 'en_US.UTF-8'),
    ('utf8', 'Café\tあいう\t€&\nüñ\t\U0001F600\tα%\n'.encode('utf-8'), 'en_US.UTF-8'),
    ('shift-jis', '表\tソフト\t能&\n十\t予\t#\n'.encode('shift_jis'), 'ja_JP.SJIS'),
    ('latin1', 'café\t£5\tå&\n'.encode('latin-1'), 'en_US.ISO8859-1'),
]


def fixture_name(name, style):
    return f'{name}.{style or "none"}.out'


def fake_clipboard(folder):
    """pbpaste and pbcopy that read and write files, and note the locale they were called with."""
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'pbpaste').write_text('#!/bin/sh\necho "$LANG $LC_ALL" > "$CSV_LOCALE"\ncat "$CSV_IN"\n')
    (folder / 'pbcopy').write_text('#!/bin/sh\ncat > "$CSV_OUT"\n')
    for name in ('pbpaste', 'pbcopy'):
        (folder / name).chmod(0o755)
    return folder


def make_fixtures(ruby):
    """Writes the inputs and the tables of the Ruby csv2latex of RUBY_COMMIT, run by RUBY."""
    script = subprocess.run(['git', 'show', f'{RUBY_COMMIT}:Resources/TeXShop/bin/csv2latex'], cwd=ROOT, capture_output=True,
                            check=True).stdout
    with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as top:
        top = Path(top)
        (top / 'csv2latex.rb').write_bytes(script)
        fake = fake_clipboard(top / 'fake')
        if FIXTURES.exists():
            shutil.rmtree(FIXTURES)
        FIXTURES.mkdir(parents=True)
        nothing = {}
        for name, data, locale in INPUTS:
            (FIXTURES / f'{name}.in').write_bytes(data)
            for style in STYLES:
                out = top / 'out'
                if out.exists():
                    out.unlink()
                env = {'PATH': f'{fake}:/usr/bin:/bin', 'LANG': locale, 'CSV_IN': str(FIXTURES / f'{name}.in'),
                       'CSV_OUT': str(out), 'CSV_LOCALE': str(top / 'locale'), 'HOME': str(top)}
                result = subprocess.run([ruby, str(top / 'csv2latex.rb'), *([style] if style else [])], env=env,
                                        capture_output=True, timeout=60)
                if result.returncode != 0:
                    sys.exit(f'{ruby} failed on {name} {style}: {result.stderr.decode(errors="replace")}')
                if out.exists():
                    (FIXTURES / fixture_name(name, style)).write_bytes(out.read_bytes())
                    if result.stdout != b'Ok. In clipboard\n':
                        sys.exit(f'{name} {style}: stdout {result.stdout!r}')
                else:
                    nothing.setdefault(name, []).append(style or 'none')
                    if result.stdout:
                        sys.exit(f'{name} {style}: stdout without a table {result.stdout!r}')
        (FIXTURES / 'nothing.json').write_text(json.dumps(nothing, indent=1, sort_keys=True) + '\n')
        version = subprocess.run([ruby, '-v'], capture_output=True, text=True).stdout.strip()
        (FIXTURES / 'README').write_text(
            'Clipboard texts (*.in) and the tables the Ruby csv2latex of TeXShop (commit '
            f'{RUBY_COMMIT}) made from them (*.<style>.out),\nwith {version}. nothing.json lists the cases where it wrote '
            'nothing.\nMade by: python3 Tests/run-csv2latex.py --make-fixtures RUBY\n')
    print(f'made {len(INPUTS)} inputs and their tables in {FIXTURES}')


def checks(scripts, top):
    """The failures of the csv2latex in the folder scripts."""
    failures = []
    nothing = json.loads((FIXTURES / 'nothing.json').read_text())
    fake = fake_clipboard(top / 'fake')
    env_base = {'PATH': f'{fake}:{TEXBIN}:/usr/bin:/bin', 'HOME': os.environ.get('HOME', str(top)), 'TMPDIR': str(top / 'tmp') + '/',
                'CFFIXED_USER_HOME': os.environ.get('CFFIXED_USER_HOME', str(top))}
    (top / 'tmp').mkdir(exist_ok=True)
    count = 0
    for name, data, _ in INPUTS:
        source = FIXTURES / f'{name}.in'
        if source.read_bytes() != data:
            failures.append(f'{name}.in is the text of the test')
        for style in STYLES:
            args = [style] if style else []
            expected_file = FIXTURES / fixture_name(name, style)
            expect_nothing = (style or 'none') in nothing.get(name, [])
            if expect_nothing == expected_file.exists():
                failures.append(f'{name} {style}: the fixtures say once what it wrote')
                continue
            expected = b'' if expect_nothing else expected_file.read_bytes()
            # csv2latex.lua alone
            lua = subprocess.run([f'{TEXBIN}/texlua', str(scripts / 'csv2latex.lua'), *args], input=data, capture_output=True,
                                 timeout=60)
            if lua.returncode != 0 or lua.stdout != expected:
                failures.append(f'csv2latex.lua {name} {style}: {lua.returncode} {lua.stdout[:200]!r} != {expected[:200]!r} '
                                f'{lua.stderr[:200]!r}')
            # csv2latex with the stand-ins of the clipboard
            out = top / 'out'
            if out.exists():
                out.unlink()
            env = dict(env_base, CSV_IN=str(source), CSV_OUT=str(out), CSV_LOCALE=str(top / 'locale'))
            sh = subprocess.run([str(scripts / 'csv2latex'), *args], env=env, capture_output=True, timeout=60)
            if sh.returncode != 0:
                failures.append(f'csv2latex {name} {style} exits with {sh.returncode}: {sh.stderr[:200]!r}')
            if expect_nothing:
                if out.exists():
                    failures.append(f'csv2latex {name} {style} leaves the clipboard alone')
                if sh.stdout:
                    failures.append(f'csv2latex {name} {style} says nothing: {sh.stdout!r}')
            else:
                if not out.exists() or out.read_bytes() != expected:
                    failures.append(f'csv2latex {name} {style} puts the table on the clipboard')
                if sh.stdout != b'Ok. In clipboard\n':
                    failures.append(f'csv2latex {name} {style} says Ok: {sh.stdout!r}')
            if (top / 'locale').read_text().split() != ['en_US.UTF-8', 'en_US.UTF-8']:
                failures.append(f'csv2latex reads the clipboard as UTF-8: {(top / "locale").read_text()!r}')
            count += 1
    leftovers = list((top / 'tmp').iterdir())
    if leftovers:
        failures.append(f'csv2latex leaves no temporary file: {leftovers}')
    if count != len(INPUTS) * len(STYLES):
        failures.append(f'all {len(INPUTS) * len(STYLES)} cases ran: {count}')
    return failures


def mutated(name, top):
    old, new = MUTATIONS[name]
    folder = top / f'bin-{name}'
    folder.mkdir()
    for file in ('csv2latex', 'csv2latex.lua'):
        text = (BIN / file).read_text()
        if old in text:
            if text.count(old) != 1:
                sys.exit(f'mutation {name} is ambiguous in {file}')
            text = text.replace(old, new)
        (folder / file).write_text(text)
        shutil.copymode(BIN / file, folder / file)
    if (folder / 'csv2latex').read_text() == (BIN / 'csv2latex').read_text() and \
       (folder / 'csv2latex.lua').read_text() == (BIN / 'csv2latex.lua').read_text():
        sys.exit(f'mutation {name} applies to nothing')
    return folder


def macro_checks():
    failures = []
    macros = plistlib.loads((ROOT / 'Resources/TeXShop/Macros/Macros_Latex.plist').read_bytes())
    found = []

    def walk(items):
        for item in items:
            if 'submenu' in item:
                walk(item['submenu'])
            elif item.get('name') == 'Paste Spreadsheet Cells':
                found.append(item.get('content', ''))
    walk(macros.get('submenu', []))
    if len(found) != 1:
        failures.append(f'one Paste Spreadsheet Cells macro: {len(found)}')
    else:
        content = found[0]
        for text in ('{"cells","booktabs", "simple","longtable" }', 'do shell script  "~/Library/TeXShop/bin/csv2latex" & " " &  tablestyle'):
            if text not in content:
                failures.append(f'the macro still has {text!r}')
    for file in ('csv2latex', 'csv2latex.lua'):
        if not (BIN / file).exists():
            failures.append(f'bin/{file} is bundled')
    if not os.access(BIN / 'csv2latex', os.X_OK):
        failures.append('bin/csv2latex is executable')
    if (BIN / 'csv2latex').read_text().startswith('#!/usr/bin/ruby'):
        failures.append('bin/csv2latex no longer needs Ruby')
    return failures


def main(mutation):
    if TEXBIN is None:
        sys.exit('FAIL: texlua of TeX Live is needed')
    with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as top:
        top = Path(top)
        scripts = mutated(mutation, top) if mutation else BIN
        failures = macro_checks() + checks(scripts, top / 'run')
        if not mutation:
            for name in MUTATIONS:
                copy = mutated(name, top)
                caught = checks(copy, top / f'run-{name}')
                if not caught:
                    failures.append(f'mutation {name} is caught')
    if failures:
        print('\n'.join('FAIL: ' + f for f in failures[:60]))
        sys.exit(1)
    print(f'PASS: csv2latex gives the tables of the former Ruby script for {len(INPUTS)} clipboard texts in {len(STYLES)} '
          f'styles ({len(INPUTS) * len(STYLES)} cases, by csv2latex.lua alone and through stand-ins for pbpaste and pbcopy '
          f'in UTF-8), leaves the clipboard alone when there is nothing to paste, the macro calls it as before, and '
          f'{len(MUTATIONS)} mutated copies are caught')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=sorted(MUTATIONS), help='run the whole test against a mutated copy (it must fail)')
    parser.add_argument('--make-fixtures', metavar='RUBY', help='write the fixtures with the Ruby csv2latex, run by RUBY')
    options = parser.parse_args()
    if options.make_fixtures:
        make_fixtures(options.make_fixtures)
    else:
        main(options.mutation)
