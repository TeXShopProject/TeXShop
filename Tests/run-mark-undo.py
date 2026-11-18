#!/usr/bin/env python3
"""Insert Mark and Next/Previous Mark (Del) can be undone, in a document and in the Experiment source.

The production methods of TSDocument and ScrapTextView are compiled verbatim (Tests/MarkUndo.m): Undo takes away
the mark, or puts it back, and nothing else, an Undo after a mark does not take other characters away, Redo works,
the action names are Insert Mark and Delete Mark, and the document counts as edited. Nothing is shown on screen.
--mutations removes each part of the undoable change and the test must then fail."""
from pathlib import Path
import os, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
signatures = ['- (BOOL)replaceMarkTextInRange:', '- (void) doNextBulletAndDelete: (id)sender', '- (void) doPreviousBulletAndDelete: (id)sender',
              '- (void) placeBullet: (id)sender']


def methods(path):
    source = (root / path).read_text(encoding='utf-8')
    found = []
    for signature in signatures:
        if signature in source:
            found.append((signature, source, method(source, signature)))
    return source, found


document_source, document = methods('Sources/Document/TSDocument.m')
scrap_source, scrap = methods('Sources/Editor/ScrapTextView.m')
fragments = [('complete method:' + s, src, f) for s, src, f in document + scrap]
harness = (root / 'Tests/MarkUndo.m').read_text(encoding='utf-8')
mutations = {
    'not through shouldChangeTextInRange': ('if (![VIEW shouldChangeTextInRange:range replacementString:string])\n        return NO;\n', ''),
    'no didChangeText': ('[VIEW didChangeText];\n', ''),
    'no action name': ('[[VIEW undoManager] setActionName:actionName];\n', ''),
}


def run(document_text, scrap_text, label):
    program = harness.replace('DOCUMENT_METHODS', document_text).replace('SCRAP_METHODS', scrap_text)
    with tempfile.TemporaryDirectory(prefix='texshop-mark-undo-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(folder / 'test.m'), '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        return subprocess.run([str(folder / 'test')], capture_output=True, text=True, timeout=120)


document_text = '\n'.join(f for _, _, f in document)
scrap_text = '\n'.join(f for _, _, f in scrap)
result = run(document_text, scrap_text, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: a mark command cannot be undone, or its Undo takes other text away')
if '--mutations' in sys.argv:
    for name, (before, after) in mutations.items():
        for which in ('document', 'scrap'):
            view = 'textView' if which == 'document' else 'self'
            old = before.replace('VIEW', view)
            d, s = document_text, scrap_text
            if which == 'document':
                assert d.count(old) == 1, (name, which); d = d.replace(old, after)
            else:
                assert s.count(old) == 1, (name, which); s = s.replace(old, after)
            r = run(d, s, name)
            assert r.returncode and 'FAIL' in r.stderr, (name, which, r.stdout, r.stderr)
            print('DETECTED', name, which, r.stderr.strip().splitlines()[-1])
print('PASS: Insert Mark and Next/Previous Mark (Del) undo and redo in documents and in the Experiment source')
