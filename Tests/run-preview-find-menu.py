#!/usr/bin/env python3
"""Preview Find commands stay on the Preview, and the source editor's Find is untouched.

Find, Find Next and Find Previous drive the toolbar search. Direction comes from the menu
tag, so a customized Find Previous still searches backward when its key has no Shift.
The existing Find All item opens the drawer and focuses the search field in its lower half.
"""
from pathlib import Path
import argparse
import re
import subprocess
import sys

MUTATIONS = {
    'again-follows-shift': (
        'Sources/Preview/MyPDFKitView.m', '- (void) doFindAgain',
        'backwards = previewFindBackwards;\n    previewFindBackwards = NO;',
        'backwards = ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) != 0;'),
    'all-stays-closed': (
        'Sources/Preview/MyPDFKitView.m', '- (void)focusDrawerSearchField',
        '        [drawer open:owner];',
        '        ;'),
    'other-find-commands-enabled': (
        'Sources/Preview/MyPDFKitView.m', '- (BOOL) validateMenuItem:(NSMenuItem *)anItem',
        '        return NO;',
        '        return YES;'),
    'full-split-steals-source-keys': (
        'Sources/Preview/MyPDFKitView.m', '- (BOOL)performKeyEquivalent:(NSEvent *)theEvent',
        '    if (([self.myDocument useFullSplitWindow]) && (! ([[self window] firstResponder] == self)))\n        return NO;\n',
        ''),
    'previous-searches-forward': (
        'Sources/Preview/MyPDFKitView.m', '- (void)doFindAgainBackwards',
        '    previewFindBackwards = YES;\n',
        ''),
}

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
sources = {}

def source(name):
    if name not in sources:
        sources[name] = (root / name).read_text(encoding='latin1')
    return sources[name]

if args.mutation:
    name, signature, old, new = MUTATIONS[args.mutation]
    text = source(name)
    start = 0
    chosen = None
    while True:
        found = text.find(signature, start)
        if found < 0:
            break
        end = text.find('\n}\n', found)
        assert end > found, args.mutation
        end += 1
        body = text[found:end]
        if old in body:
            assert chosen is None, args.mutation
            chosen = (found, end, body)
        start = end
    assert chosen is not None, args.mutation
    found, end, body = chosen
    assert body.count(old) == 1, (args.mutation, body.count(old))
    sources[name] = text[:found] + body.replace(old, new, 1) + text[end:]

def code(text):
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)

def methods(text):
    text = code(text)
    starts = [m.start() for m in re.finditer(r'^[-+] *\(', text, re.M)] + [len(text)]
    for a, b in zip(starts, starts[1:]):
        chunk = text[a:b]
        head = chunk.split('\n')[0]
        if head.rstrip().endswith(';'):
            continue
        yield head, chunk

def method(name, signature, contains=None):
    found = [body for head, body in methods(source(name)) if head.startswith(signature)]
    if contains:
        found = [body for body in found if contains in body]
    if len(found) != 1:
        return ''
    return found[0]

problems = []
def expect(ok, message):
    if not ok:
        problems.append(message)

kit = 'Sources/Preview/MyPDFKitView.m'
again = method(kit, '- (void) doFindAgain')
expect('NSShiftKeyMask' not in again and 'NSEventModifierFlagShift' not in again,
       'Find Next follows the Shift key instead of the menu command')
expect('previewFindBackwards = NO' in again and again.index('previewFindBackwards = NO') < again.index('findString:'),
       'Find Previous stays backward for the next Find Next')
expect(0 <= again.find('if (searchSelection != NULL)') <
       again.find('[(MyPDFKitView *)self.myDocument.pdfKitWindow.activeView keepPinnedLinkPreviewThroughMove]') <
       again.find('[self.myDocument.pdfKitWindow.activeView goToPage: thePage]'),
       'toolbar search no longer keeps the pinned link popup on its page')
for signature in ('- (void) doFindOne:', '- (void) doFindOneFullWindow:'):
    body = method(kit, signature)
    expect('NSShiftKeyMask' in body, f'{signature} no longer searches backward on Shift-Return')

keys = method(kit, '- (BOOL)performPreviewFindKeyEquivalent:(NSEvent *)theEvent')
for tag in (1, 2, 3):
    expect(f'tag:{tag}]' in keys, f'Preview no longer matches Find command {tag}, including a customized key')
expect('TSAdvancedFindActionFindAll' in keys, 'the existing Find All item is not matched')
guard = method(kit, '- (BOOL)performKeyEquivalent:(NSEvent *)theEvent', 'useFullSplitWindow')
expect(guard and guard.index('return NO') < guard.index('performPreviewFindKeyEquivalent:'),
       'the combined window handles Preview Find while the source editor is first responder')
field_editor = method(kit, '- (BOOL)performKeyEquivalent:(NSEvent *)theEvent', 'self.owner')
expect('useFullSplitWindow' not in field_editor and 'performPreviewFindKeyEquivalent:' in field_editor,
       'Find keys typed in the Preview search field of the combined window are dropped')

validate = method(kit, '- (BOOL) validateMenuItem:(NSMenuItem *)anItem')
find = validate[validate.find('performFindPanelAction:'):]
expect('NSFindPanelActionShowFindPanel' in find and 'NSFindPanelActionNext' in find and
       'NSFindPanelActionPrevious' in find and 'TSAdvancedFindActionFindAll' in find and
       find.find('return NO;') >= 0 and
       find.find('return NO;') < find.find('return [super validateMenuItem:'),
       'Preview enables Find commands other than Find, Find Next, Find Previous and Find All')
expect('previewFindBackwards = YES' in method(kit, '- (void)doFindAgainBackwards'),
       'Find Previous searches forward')

drawer = method(kit, '- (void)focusDrawerSearchField')
expect('[drawer open:owner]' in drawer and 'focusDrawerSearchWhenOpen = YES' in drawer and
       'NSDrawerOpenState' in drawer and 'focusSearchField:' in method(kit, '- (void)previewDrawerDidOpen:'),
       'Find All does not open a closed drawer and focus its search field')

editor = method(kit, '- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client')
expect('myPDFWindow' in editor and '_drawer.contentView.window' in editor,
       'the Preview search fields keep the ordinary field editor')
combined = method('Sources/Document/TSDocument.m',
                  '- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client')
expect('sender != fullSplitWindow' in combined and 'return nil' in combined and
       'isPreviewSearchClient:' not in combined and 'previewFindFieldEditorForWindow:sender client:client' in combined,
       'the combined window changes the field editor of something other than a Preview search field')
source_find = method('Sources/Editor/TSTextView.m', '- (void)performFindPanelAction:(id)sender')
expect('advancedFind' in source_find and '[super performFindPanelAction:sender]' in source_find,
       'the source editor no longer performs its own Find commands')
source_window = method('Sources/Windows/TSTextEditorWindow.m', '- (void)performFindPanelAction:')
expect('[self.myDocument.textView performFindPanelAction:sender]' in source_window and 'MyPDFKitView' not in source_window,
       'the source window runs Preview Find')
split_window = method('Sources/Windows/TSFullSplitWindow.m', '- (void)performFindPanelAction:')
expect('NSLog(@"oh no")' in split_window and 'doFindAgain' not in split_window and 'focusDrawerSearchField' not in split_window,
       'the combined window runs Preview Find when the source side is first responder')

if problems:
    print('FAIL', file=sys.stderr)
    for problem in problems:
        print(problem, file=sys.stderr)
    sys.exit(1)
print('PASS: Preview Find uses the toolbar and the drawer, and the source editor is unchanged')

if args.mutation:
    sys.exit(0)
for name in MUTATIONS:
    result = subprocess.run([sys.executable, __file__, '--mutation', name], cwd=root)
    if result.returncode == 0:
        print('MISSED', name, file=sys.stderr)
        sys.exit(1)
    print('DETECTED', name)
