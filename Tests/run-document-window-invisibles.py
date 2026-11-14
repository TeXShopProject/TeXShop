#!/usr/bin/env python3
"""Open the document nib of every language with the production invisible-character code.

TeXShop 5.57 to 5.60 could not open a document window in Romanian: the Romanian
TSDocument.nib connected the textView outlet to the plain text view of the text
annotation panel, and windowControllerDidLoadNib: sent the TSLayoutManager-only
setInvisibleCharactersEnabled: to its NSLayoutManager. This loads each compiled
TSDocument.nib with TSTextView's production layout manager replacement and
TSDocument's production setTextView:, applyInvisibleCharactersShowing and
showHideInvisibleCharacters:, then shows and hides invisible characters in a
single and a split source. A text view without a TSLayoutManager must be skipped.

--nibs-from REV loads the compiled nibs of an older revision (for example the
commit before the fix, to reproduce the failure); --mutation checks that the
checks catch a missing guard.
"""
import argparse, re, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
from source_tree import include_args, source_file

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--nibs-from', metavar='REV')
parser.add_argument('--mutation', choices=['unguarded'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
document = source_file(root, 'TSDocument.m').read_text(encoding='utf-8')
text_view = source_file(root, 'TSTextView.m').read_text(encoding='utf-8')
globals_m = source_file(root, 'globals.m').read_text(encoding='latin-1')

fragments = []
methods = []
for signature in ('- (void) applyInvisibleCharactersShowing', '- (void) showHideInvisibleCharacters: sender', '- (void) setTextView: (id)aView'):
    body = method(document, signature)
    fragments.append(('method:' + signature, document, body)); methods.append(body)
first = '\tTSLayoutManager *layoutManager = [[TSLayoutManager alloc] init];'
last = '[[self textContainer] replaceLayoutManager:layoutManager];'
start = text_view.index(first); end = text_view.index(last, start) + len(last)
replacement = text_view[start:end]
assert text_view.count(replacement) == 1
fragments.append(('statements:TSTextView layout manager', text_view, replacement))

harness = (root / 'Tests/DocumentWindowInvisibles.m').read_text(encoding='utf-8')
harness = harness.replace('    //@@TSTextView layout manager@@', replacement)
harness = harness.replace('//@@TSDocument methods@@', '\n\n'.join(methods))
verify_embedded(harness, fragments)
if args.mutation == 'unguarded':
    guarded = methods[0]
    unguarded = ('- (void) applyInvisibleCharactersShowing\n{\n'
                 '\t[(TSLayoutManager*)[textView layoutManager] setInvisibleCharactersEnabled:invisibleCharactersShowing];\n'
                 '\t[(TSLayoutManager*)[textView1 layoutManager] setInvisibleCharactersEnabled:invisibleCharactersShowing];\n'
                 '\t[(TSLayoutManager*)[textView2 layoutManager] setInvisibleCharactersEnabled:invisibleCharactersShowing];\n'
                 '\t[self applyExperimentInvisibleCharacters];\n}')
    assert 'isKindOfClass:[TSLayoutManager class]' in guarded, 'The production method checks the layout manager'
    harness = harness.replace(guarded, unguarded)

keys = re.findall(r'^NSString \*(?:show(?:Space|FullwidthSpace|Tab|NewLine)CharacterKey|(?:Space|FullwidthSpace|Tab|NewLine)CharacterKindKey)\s*=.*?;', globals_m, re.M)
assert len(keys) == 8
with tempfile.TemporaryDirectory(prefix='texshop-document-invisibles-') as tmp:
    tmp = Path(tmp)
    (tmp / 'MarkerKeys.h').write_text('\n'.join(keys))
    (tmp / 'harness.m').write_text(harness, encoding='utf-8')
    exe = tmp / 'harness'
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit', '-I', str(tmp), '-I', str(root / 'Tests'),
                    *include_args(root), str(tmp / 'harness.m'), str(source_file(root, 'TSLayoutManager.m')),
                    str(source_file(root, 'TSAdvancedFindHighlights.m')), '-o', str(exe)], check=True)
    nibs = sorted((root / 'Resources/Interfaces').glob('*.lproj/TSDocument.nib/keyedobjects.nib'))
    assert len(nibs) == 12, 'TSDocument.nib in 12 languages'
    failed = []
    for nib in nibs:
        path = nib
        if args.nibs_from:
            path = tmp / (nib.parent.parent.name + '.nib')
            path.write_bytes(subprocess.check_output(['git', 'show', '%s:%s' % (args.nibs_from, nib.relative_to(root))], cwd=root))
        result = subprocess.run([str(exe), str(path)], capture_output=True, text=True, timeout=120)
        out = result.stdout.replace(str(path), str(nib.relative_to(root)))
        print(out, end='')
        if result.returncode:
            failed.append(nib.parent.parent.name)
            if result.returncode != 1:
                print('CRASH %s (exit %d): %s' % (nib.relative_to(root), result.returncode, result.stderr.strip().splitlines()[-1:] or ''))
    if failed:
        sys.exit('FAIL: ' + ', '.join(failed))
    print('PASS: the document window of all 12 languages shows and hides invisible characters')
