#!/usr/bin/env python3
"""The PreTeXt-Validate engine reports whether the PreTeXt file follows the PreTeXt schema.

The engine (Resources/TeXShop/Engines/Inactive/PreTeXt/PreTeXt-Validate.engine, and its copy in
DocumentSources/PreTeXt/PreTeXt, which must be the same) runs xmllint of macOS with the schema
~/Documents/mathbook/schema/pretext.rng. It is run here as TeXShop runs an engine: the engine file itself, with the
file name, the parameter (" " when there is none) and the TeX bin path as arguments, in the folder of the file, which
has a space, a quote and a dollar sign in its name. HOME is a private folder holding a small RNG schema at that path.

- a valid file: exit status 0, "Finished. <file> is valid." and no error message;
- a file against the schema: exit status 3 (that of xmllint), the error of xmllint and "does not follow the PreTeXt
  schema" on standard error, no "Finished";
- a file that is not well-formed XML: exit status 1, the parser error and "is not well-formed XML", no "Finished";
- no schema: exit status 1 and a message naming the missing schema, xmllint not run, no "Finished".

Mutated copies of the engine (MUTATIONS) must each fail the test; --mutation NAME runs the whole test against one.
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / 'Resources/TeXShop/Engines/Inactive/PreTeXt/PreTeXt-Validate.engine'
COPY = ROOT / 'DocumentSources/PreTeXt/PreTeXt/PreTeXt-Validate.engine'
TEXBIN = next((d for d in ['/Applications/TeXLive/2026/bin/universal-darwin', '/Library/TeX/texbin'] if Path(d).is_dir()),
              '/Library/TeX/texbin')
SCHEMA = '''<grammar xmlns="http://relaxng.org/ns/structure/1.0">
  <start>
    <element name="pretext">
      <element name="article">
        <element name="title"><text/></element>
        <oneOrMore><element name="p"><text/></element></oneOrMore>
      </element>
    </element>
  </start>
</grammar>
'''
VALID = '<?xml version="1.0" encoding="UTF-8"?>\n<pretext><article><title>T</title><p>Hello.</p></article></pretext>\n'
AGAINST_SCHEMA = '<?xml version="1.0" encoding="UTF-8"?>\n<pretext><article><p>No title.</p></article></pretext>\n'
NOT_WELL_FORMED = '<?xml version="1.0" encoding="UTF-8"?>\n<pretext><article><title>T</title>\n'
MUTATIONS = {
    # the engine ends with an echo again, so its status is always 0 (6.00 RC 2)
    'ends-with-echo': ('exit $result\n', 'echo "Finished. No news is good news."\n'),
    # xmllint runs without the schema
    'no-schema-check': ('if [[ ! -f "$schema" ]]; then', 'if false; then'),
    # the finished message comes whatever xmllint says
    'finished-always': ('case $result in\n', 'echo "Finished. $1 is valid."\ncase $result in\n'),
}
failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def mutated(name, top):
    old, new = MUTATIONS[name]
    text = ENGINE.read_text()
    if text.count(old) != 1:
        sys.exit(f'mutation {name} does not apply once to the engine')
    copy = top / f'engine-{name}' / ENGINE.name
    copy.parent.mkdir()
    copy.write_text(text.replace(old, new))
    shutil.copymode(ENGINE, copy)
    return copy


def run_engine(engine, folder, name, home, tmp):
    # TeXShop: launch path = the engine, arguments = file name, parameter (" "), TeX bin path; current folder = the file's.
    env = {'PATH': f'{TEXBIN}:/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(home), 'CFFIXED_USER_HOME': str(home),
           'TMPDIR': str(tmp) + '/', 'LANG': 'en_US.UTF-8'}
    return subprocess.run([str(engine), name, ' ', TEXBIN], cwd=folder, env=env, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=60)


def file_checks():
    check(ENGINE.read_bytes() == COPY.read_bytes(), 'the engine and its copy in DocumentSources are the same')
    for engine in (ENGINE, COPY):
        check(os.access(engine, os.X_OK), f'{engine.relative_to(ROOT)} is executable')
    check(ENGINE.read_text().startswith('#!/bin/zsh\n'), 'the engine is a zsh script')
    check('jing' not in ENGINE.read_text().replace('ran jing', ''), 'the engine does not run jing')


def engine_checks(engine, top):
    home = top / 'home'
    schema = home / 'Documents/mathbook/schema/pretext.rng'
    schema.parent.mkdir(parents=True)
    schema.write_text(SCHEMA)
    tmp = top / 'tmp'
    tmp.mkdir()
    folder = top / 'my "book" $HOME'
    folder.mkdir()
    name = 'a b.ptx'

    cases = [('valid', VALID, 0, 'Finished. a b.ptx is valid.', None),
             ('against the schema', AGAINST_SCHEMA, 3, 'PreTeXt-Validate: a b.ptx does not follow the PreTeXt schema',
              'Relax-NG validity error'),
             ('not well-formed', NOT_WELL_FORMED, 1, 'PreTeXt-Validate: a b.ptx is not well-formed XML', 'parser error')]
    for label, text, status, message, xmllint_says in cases:
        (folder / name).write_text(text)
        result = run_engine(engine, folder, name, home, tmp)
        output = result.stdout + result.stderr
        check(result.returncode == status, f'{label}: exit status {status}: {result.returncode} {output[-300:]!r}')
        if status == 0:
            check(result.stdout.strip() == message, f'{label}: says "{message}" on standard output: {result.stdout!r}')
            check('a b.ptx validates' in result.stderr and 'PreTeXt-Validate:' not in result.stderr,
                  f'{label}: no error message: {result.stderr!r}')
        else:
            check(message in result.stderr, f'{label}: says "{message}" on standard error: {result.stderr[-300:]!r}')
            check(xmllint_says in result.stderr, f'{label}: the xmllint error "{xmllint_says}" is shown: {result.stderr[:300]!r}')
            check('Finished' not in output and 'is valid' not in output, f'{label}: no finished message: {output[-300:]!r}')

    (folder / name).write_text(VALID)
    schema.unlink()
    result = run_engine(engine, folder, name, home, tmp)
    output = result.stdout + result.stderr
    check(result.returncode != 0, f'no schema: exit status not 0: {result.returncode}')
    check(f'the PreTeXt schema {schema} is not found' in result.stderr,
          f'no schema: names the missing schema: {result.stderr!r}')
    check('validates' not in output and 'xmllint' not in output and 'Finished' not in output,
          f'no schema: xmllint is not run and nothing says finished: {output!r}')
    check(not any(tmp.iterdir()), f'nothing is left in TMPDIR: {list(tmp.iterdir())}')
    check(sorted(p.name for p in folder.iterdir()) == [name], f'nothing is written beside the file: {list(folder.iterdir())}')


def main(mutation):
    global failures
    if not Path('/usr/bin/xmllint').exists():
        sys.exit('FAIL: /usr/bin/xmllint is needed')
    with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as top:
        top = Path(top)
        if mutation:
            engine_checks(mutated(mutation, top), top / 'run')
        else:
            file_checks()
            (top / 'run').mkdir()
            engine_checks(ENGINE, top / 'run')
            for name in MUTATIONS:
                kept, failures = failures, []
                (top / f'run-{name}').mkdir()
                engine_checks(mutated(name, top), top / f'run-{name}')
                caught, failures = failures, kept
                check(caught, f'mutation {name} is caught')
    if failures:
        print('\n'.join('FAIL: ' + f for f in failures))
        sys.exit(1)
    print('PASS: PreTeXt-Validate, run as TeXShop runs an engine, exits 0 with its finished message only for a valid file, '
          'exits with the status of xmllint (3 against the schema, 1 not well-formed) with its error and a message, '
          'stops with status 1 naming the missing schema, and is the same in DocumentSources; '
          f'{len(MUTATIONS)} mutated copies are caught')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=sorted(MUTATIONS), help='run the whole test against a mutated copy (it must fail)')
    main(parser.parse_args().mutation)
