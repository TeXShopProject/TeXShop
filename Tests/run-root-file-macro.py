#!/usr/bin/env python3
"""Macros › Set Root File… finds the relative path of the root file in AppleScript, for paths with any character.

Up to 6.00 RC 2 the macro (then called Root) put both paths in a Perl string inside "perl -e '…'", so a path with " $ @
' or a backslash in it gave a wrong path or an error. The handler relative_root_path at the end of the macro is now
taken out of Macros_Latex.plist and run by osascript alone (TeXShop is not started or driven). Its result must be:

- for ordinary paths, what the Perl command of the earlier macro gave, run as the macro ran it, so that the line
  "% !TEX root = …" stays the same: the same folder, the folder above, a folder below, other folders, the top folder,
  a document at the top, spaces, dots, names that differ only in case (Perl compared exactly);
- for paths with " $ @ ' \\ ` ; & * ? ! %, spaces, Japanese, accented letters in NFC and NFD and an emoji, what
  File::Spec->abs2rel gives when the paths are passed as arguments (no quoting), and what Python's posixpath.relpath
  gives; the earlier Perl command is shown to fail or to be wrong for each path with " $ @ ' or \\.

The macro must no longer run Perl, dirname or any shell command, and must still write "% !TEX root = " & root.
Each mutation (a copy of the handler with one change) must be caught. --mutation NAME runs the test against it.
"""
from pathlib import Path
import argparse
import os
import plistlib
import posixpath
import subprocess
import sys
import tempfile
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
MACROS = ROOT / 'Resources/TeXShop/Macros/Macros_Latex.plist'
MUTATIONS = {
    'ignore-case': ('if id of (item (common + 1) of target_names) is not id of (item (common + 1) of base_names) then exit repeat',
                    'if item (common + 1) of target_names is not item (common + 1) of base_names then exit repeat'),
    'keep-document-name': ('if (count of base_names) > 0 then set base_names to reverse of rest of reverse of base_names',
                           'set base_names to base_names'),
    'no-updir': ('set end of relative_names to ".."', 'set end of relative_names to "."'),
    'first-difference-kept': ('repeat with i from common + 1 to count of target_names', 'repeat with i from common + 2 to count of target_names'),
}

# (root file, document): ordinary paths, for which the earlier Perl command worked.
ORDINARY = [
    ('/Users/ann/Paper/main.tex', '/Users/ann/Paper/intro.tex'),
    ('/Users/ann/Paper/main.tex', '/Users/ann/Paper/chapters/one.tex'),
    ('/Users/ann/Paper/main.tex', '/Users/ann/Paper/parts/a/b/c.tex'),
    ('/Users/ann/Paper/sub/main.tex', '/Users/ann/Paper/intro.tex'),
    ('/Users/ann/Book/main.tex', '/Users/ann/Paper/chapters/one.tex'),
    ('/Volumes/Data/main.tex', '/Users/ann/Paper/one.tex'),
    ('/main.tex', '/Users/ann/one.tex'),
    ('/Users/ann/main.tex', '/one.tex'),
    ('/main.tex', '/one.tex'),
    ('/Users/ann/My Paper/main file.tex', '/Users/ann/My Paper/Chapter 1/one.tex'),
    ('/Users/ann/v1.2/main.v2.tex', '/Users/ann/v1.2/x.y/one.tex'),
    ('/Users/ann/paper/main.tex', '/Users/ann/Paper/one.tex'),
    ('/Users/ann/Paper/main', '/Users/ann/Paper/one.tex'),
]
# Paths the earlier macro could not take: (root file, document).
SPECIAL = [
    ('/Users/ann/Say "Hi"/main.tex', '/Users/ann/Say "Hi"/ch/one.tex'),
    ('/Users/ann/"q"/main.tex', '/Users/ann/other/one.tex'),
    ('/Users/ann/Cost $5/main.tex', '/Users/ann/other/one.tex'),
    ('/Users/ann/$HOME/main.tex', '/Users/ann/x/one.tex'),
    ('/Users/ann/a/main.tex', '/Users/ann/$x/one.tex'),
    ('/Users/ann/user@mail/main.tex', '/Users/ann/other/one.tex'),
    ("/Users/ann/Ann's Paper/main.tex", "/Users/ann/Ann's Paper/ch/one.tex"),
    ('/Users/ann/back\\slash/main.tex', '/Users/ann/x/one.tex'),
    ('/Users/ann/tick`date`/main.tex', '/Users/ann/x/one.tex'),
    ('/Users/ann/a;b&c|d/main.tex', '/Users/ann/a;b&c|d/e*f?/one.tex'),
    ('/Users/ann/!bang %20/main.tex', '/Users/ann/x/one.tex'),
    ('/Users/ann/論文/本文.tex', '/Users/ann/論文/章/第一章.tex'),
    ('/Users/ann/' + unicodedata.normalize('NFC', 'Résumé') + '/main.tex', '/Users/ann/' + unicodedata.normalize('NFC', 'Résumé') + '/x/one.tex'),
    ('/Users/ann/' + unicodedata.normalize('NFD', 'Résumé') + '/main.tex', '/Users/ann/' + unicodedata.normalize('NFD', 'Résumé') + '/one.tex'),
    ('/Users/ann/' + unicodedata.normalize('NFD', 'Résumé') + '/main.tex', '/Users/ann/' + unicodedata.normalize('NFC', 'Résumé') + '/one.tex'),
    ('/Users/ann/😀 paper/main.tex', '/Users/ann/😀 paper/one.tex'),
    ('/Users/ann/"$@\'\\`/main.tex', '/Users/ann/"$@\'\\`/a/b/one.tex'),
]


def macro_content():
    macros = plistlib.loads(MACROS.read_bytes())
    found = []

    def walk(items):
        for item in items:
            if 'submenu' in item:
                walk(item['submenu'])
            elif item.get('name') == 'Set Root File…':
                found.append(item.get('content', ''))
    walk(macros.get('submenu', []))
    if len(found) != 1:
        sys.exit(f'FAIL: one Set Root File… macro: {len(found)}')
    return found[0]


def handler(content):
    start = content.index('on relative_root_path(')
    end = content.index('end relative_root_path') + len('end relative_root_path')
    return content[start:end]


def run_handler(code, pairs, tmp):
    """The relative paths the handler gives for (root file, document) pairs, run by osascript."""
    script = Path(tmp) / 'relative.applescript'
    script.write_text(code + '\n\non run argv\n\tset results to {}\n\trepeat with i from 1 to count of argv by 2\n'
                      '\t\tset end of results to relative_root_path(item i of argv, item (i + 1) of argv)\n\tend repeat\n'
                      '\tset AppleScript\'s text item delimiters to linefeed\n\treturn results as text\nend run\n', encoding='utf-8')
    args = [part for pair in pairs for part in pair]
    result = subprocess.run(['/usr/bin/osascript', str(script), *args], capture_output=True, timeout=60,
                            env={'PATH': '/usr/bin:/bin', 'HOME': os.environ.get('HOME', tmp), 'TMPDIR': tmp + '/',
                                 'CFFIXED_USER_HOME': os.environ.get('CFFIXED_USER_HOME', tmp)})
    if result.returncode != 0:
        return None, result.stderr.decode('utf-8', 'replace')
    return result.stdout.decode('utf-8').rstrip('\n').split('\n'), ''


def perl_arguments(root, document):
    """File::Spec->abs2rel with the paths given as arguments, which needs no quoting."""
    return subprocess.run(['/usr/bin/perl', '-MFile::Spec', '-e', 'print File::Spec->abs2rel($ARGV[0], $ARGV[1])',
                           root, posixpath.dirname(document)], capture_output=True, check=True).stdout.decode('utf-8')


def perl_as_before(root, document):
    """The command the earlier macro ran, built the same way: (exit status, output)."""
    base = posixpath.dirname(document)
    command = ("perl -e 'use File::Spec; $rel_path = File::Spec->abs2rel" + '( "' + root + '",' + '"' + base + '" ) ; '
               + "print $rel_path'")
    result = subprocess.run(['/bin/sh', '-c', command], capture_output=True, timeout=30, env={'PATH': '/usr/bin:/bin'})
    return result.returncode, result.stdout.decode('utf-8', 'replace')


def checks(code, tmp):
    failures = []
    pairs = ORDINARY + SPECIAL
    results, error = run_handler(code, pairs, tmp)
    if results is None or len(results) != len(pairs):
        return [f'osascript runs the handler: {error or results}']
    for (root, document), got in zip(ORDINARY, results[:len(ORDINARY)]):
        status, before = perl_as_before(root, document)
        if status != 0 or got != before:
            failures.append(f'{root} from {document}: {got!r}, earlier macro {before!r} ({status})')
    for (root, document), got in zip(SPECIAL, results[len(ORDINARY):]):
        expected = perl_arguments(root, document)
        if got != expected or got != posixpath.relpath(root, posixpath.dirname(document)):
            failures.append(f'{root!r} from {document!r}: {got!r}, expected {expected!r}')
    return failures


def main(mutation):
    content = macro_content()
    failures = []
    for gone in ('perl', 'do shell script', 'dirname', 'File::Spec->abs2rel"'):
        if gone in content:
            failures.append(f'the macro no longer has {gone!r}')
    for kept in ('set Root_rel_path to my relative_root_path(Root_abs_path, TeX_path)', 'set roots to {Root_rel_path, Root_abs_path}',
                 'set program to "% !TEX root = " & root & linefeed', 'POSIX path of (choose file with prompt "Pick the Root document:")'):
        if kept not in content:
            failures.append(f'the macro has {kept!r}')
    code = handler(content)
    with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as tmp:
        if mutation:
            old, new = MUTATIONS[mutation]
            if code.count(old) != 1:
                sys.exit(f'FAIL: mutation {mutation} applies once')
            code = code.replace(old, new)
        failures += checks(code, tmp)
        # The earlier command broke on each of these paths with " $ @ ' or a backslash.
        broken = 0
        for root, document in SPECIAL:
            if not any(c in root + document for c in '"$@\'\\'):
                continue
            status, before = perl_as_before(root, document)
            if status != 0 or before != perl_arguments(root, document):
                broken += 1
            else:
                failures.append(f'the earlier Perl command breaks on {root!r} from {document!r}')
        if not mutation:
            for name, (old, new) in MUTATIONS.items():
                if code.count(old) != 1:
                    failures.append(f'mutation {name} applies once')
                elif not checks(code.replace(old, new), tmp):
                    failures.append(f'mutation {name} is caught')
    if failures:
        print('\n'.join('FAIL: ' + f for f in failures))
        sys.exit(1)
    print(f'PASS: Set Root File… finds the relative path in AppleScript: {len(ORDINARY)} ordinary paths give what the earlier Perl '
          f'command gave, {len(SPECIAL)} paths with quotes, $, @, backslashes, shell characters, Japanese, NFC/NFD accents and '
          f'an emoji give File::Spec->abs2rel and posixpath.relpath ({broken} of them broke the earlier command), the macro '
          f'runs no shell, and {len(MUTATIONS)} mutated handlers are caught')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mutation', choices=sorted(MUTATIONS), help='run the test against a mutated handler (it must fail)')
    main(parser.parse_args().mutation)
