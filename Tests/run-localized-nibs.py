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

The annotation window lays transparent buttons over a picture of the annotation
kinds. In every language they must keep the place they have over the picture in
Base: the French window moved the picture 68 points to the right but not the buttons,
so they covered the buttons on the left and missed the kinds they name.
"""
import argparse, json, shutil, subprocess, sys, tempfile
import xml.etree.ElementTree as ElementTree
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
                    for fact, count in items.items():
                        entry = next((e for e in allowed if e['nib'] == kind and e['change'] == change and e['fact'] == fact and code in e['languages']), None)
                        if entry is None:
                            problems.append('%s %s/%s: %s %s' % (kind, lang.name, name, change, fact))
                        elif count != entry.get('count', 1):
                            # A listed difference occurs exactly as often as listed in every compiled variant.
                            problems.append('%s %s/%s: %s %d times instead of %d: %s' % (kind, lang.name, name, change, count, entry.get('count', 1), fact))
                        else:
                            seen.add((kind, change, fact, code))
    for e in allowed:
        for code in e['languages']:
            if (e['nib'], e['change'], e['fact'], code) not in seen:
                problems.append('listed difference no longer occurs (%s, %s): %s %s' % (e['nib'], code, e['change'], e['fact']))
    print('Compared %d compiled localized nibs with Base' % checked)

    def annotation_buttons(designable):
        tree = ElementTree.parse(designable).getroot()
        ids = {e.get('id'): e for e in tree.iter() if e.get('id')}
        window = ids[next(o for o in tree.iter('outlet') if o.get('property') == 'annotationChoices').get('destination')]
        views = list(window.find('view/subviews'))
        picture = [v for v in views if v.tag == 'imageView']
        assert len(picture) == 1, designable
        px, py = (float(picture[0].find('rect').get(k)) for k in 'xy')
        frames = []
        for v in views:
            cell = v.find('buttonCell')
            if v.tag == 'button' and cell is not None and cell.get('transparent') == 'YES':
                r = v.find('rect'); action = v.find('connections/action')
                frames.append((action.get('selector') if action is not None else None,
                               float(r.get('x')) - px, float(r.get('y')) - py, float(r.get('width')), float(r.get('height'))))
        return Counter(frames)

    base_buttons = annotation_buttons(interfaces / 'Base.lproj/TSDocument.nib/designable.nib')
    assert sum(base_buttons.values()) == 12 and any(f[0] == 'strikeoutAnnotation:' for f in base_buttons), base_buttons
    for designable in sorted(interfaces.glob('*.lproj/TSDocument.nib/designable.nib')):
        ours = annotation_buttons(designable)
        for frame in sorted((base_buttons - ours) + (ours - base_buttons), key=str):
            problems.append('TSDocument %s: the annotation button %s is not where Base puts it over the picture: %s'
                            % (designable.parent.parent.name, frame[0], 'missing' if frame in base_buttons else frame[1:]))
    print('Compared the annotation buttons of %d document nibs with Base' % len(list(interfaces.glob('*.lproj/TSDocument.nib/designable.nib'))))

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
