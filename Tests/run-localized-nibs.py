#!/usr/bin/env python3
"""Compare every localized nib with the Base nib, as AppKit loads it.

NibFacts.m loads a compiled nib without showing anything and lists what it does:
the class of every object (custom classes included), every outlet, action,
binding, delegate, data source, tag and identifier, and where each object sits.
For every nib that the app loads, each language's compiled variants must match
the Base nib except for the differences listed, with a reason, in
localized-nib-differences.json; a listed difference that no longer occurs must be
removed from the list. Each designable.nib, compiled now with ibtool, must also
match the compiled nibs next to it, so that no source change waits for a compile.

The Romanian document nib once connected the editor outlet to the text
annotation panel (#42); the Spanish one the Previous button to the log window;
ten matrix panels named a class that no longer exists.
"""
import argparse, json, shutil, subprocess, sys, tempfile
from collections import Counter
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--skip-compile', action='store_true', help='skip the designable.nib check')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
allowed = json.loads((root / 'Tests/localized-nib-differences.json').read_text(encoding='utf-8'))
project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text(encoding='utf-8')

# Preferences.nib is the historical settings window: it stays in the tree but is not
# copied into the app. Every other localized nib is.
kinds = sorted(p.stem for p in (interfaces / 'Base.lproj').glob('*.nib'))
assert 'Preferences.nib in Resources' not in project, 'Preferences.nib is not built'
kinds.remove('Preferences')
for kind in kinds:
    assert '/* %s.nib in Resources */' % kind in project, kind + '.nib is copied into the app'
assert len(kinds) == 7, kinds


def variants(nib):
    if nib.is_file():
        return {'keyedobjects.nib': nib}
    return {p.name: p for p in sorted(nib.glob('keyedobjects*.nib'))}


with tempfile.TemporaryDirectory(prefix='texshop-localized-nibs-') as tmp:
    tmp = Path(tmp)
    exe = tmp / 'nibfacts'
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-I', str(root / 'Tests'), '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-framework', 'AVKit', '-framework', 'WebKit', '-framework', 'Quartz', str(root / 'Tests/NibFacts.m'), '-o', str(exe)], check=True)

    def facts(path):
        result = subprocess.run([str(exe), str(path)], capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise SystemExit('Cannot load %s: %s' % (path, result.stderr.strip()[-400:]))
        return Counter(json.loads(result.stdout))

    problems = []
    seen = set()
    checked = 0
    for kind in kinds:
        base = {name: facts(path) for name, path in variants(interfaces / 'Base.lproj' / (kind + '.nib')).items()}
        assert base, kind
        for lang in sorted(p for p in interfaces.glob('*.lproj') if p.name != 'Base.lproj'):
            nib = lang / (kind + '.nib')
            if not nib.exists():
                continue
            code = lang.name[:-len('.lproj')]
            for name, path in variants(nib).items():
                ours = facts(path); theirs = base.get(name) or base['keyedobjects.nib']
                checked += 1
                for change, items in (('missing', theirs - ours), ('extra', ours - theirs)):
                    for fact in items:
                        entry = next((e for e in allowed if e['nib'] == kind and e['change'] == change and e['fact'] == fact and code in e['languages']), None)
                        if entry is None:
                            problems.append('%s %s/%s: %s %s' % (kind, lang.name, name, change, fact))
                        else:
                            seen.add((kind, change, fact, code))
    for e in allowed:
        for code in e['languages']:
            if (e['nib'], e['change'], e['fact'], code) not in seen:
                problems.append('listed difference no longer occurs (%s, %s): %s %s' % (e['nib'], code, e['change'], e['fact']))
    print('Compared %d compiled localized nibs with Base' % checked)

    if not args.skip_compile:
        compiled = 0
        for designable in sorted(interfaces.glob('*.lproj/*.nib/designable.nib')):
            nib = designable.parent
            if nib.stem == 'Preferences':
                continue
            work = tmp / 'compile'; shutil.rmtree(work, ignore_errors=True); work.mkdir()
            shutil.copy2(designable, work / 'in.xib')
            subprocess.run(['xcrun', 'ibtool', '--compile', str(work / 'out.nib'), str(work / 'in.xib')], check=True, capture_output=True)
            out = work / 'out.nib'
            fresh = variants(out) if out.is_dir() else {'keyedobjects.nib': out}
            for name, path in variants(nib).items():
                source = fresh.get(name) or fresh['keyedobjects.nib']
                if facts(source) != facts(path):
                    problems.append('%s/%s differs from its designable.nib; compile it again' % (nib.relative_to(interfaces), name))
                compiled += 1
        print('Compared %d compiled nibs with their designable.nib' % compiled)

    if problems:
        print('\n'.join('FAIL ' + p for p in problems))
        sys.exit('FAIL: %d differences' % len(problems))
    print('PASS: every localized nib does what the Base nib does, apart from %d listed differences' % len(allowed))
