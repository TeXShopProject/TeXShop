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
    # Find All must not run a search.
    'all-runs-search': (
        'Sources/Preview/MyPDFKitView.m', '- (void)focusDrawerSearchField',
        '        [owner focusSearchField:field];\n        return;\n',
        '        [owner focusSearchField:field];\n        [owner doFind:field];\n        return;\n'),
    # An open drawer still moves focus to its search field.
    'open-drawer-no-focus': (
        'Sources/Preview/MyPDFKitView.m', '- (void)focusDrawerSearchField',
        '        [owner focusSearchField:field];\n',
        ''),
    # The Preview window itself validates Find.
    'preview-window-disables-find': (
        'Sources/Windows/TSPreviewWindow.m', '- (BOOL)validateMenuItem:(NSMenuItem *)anItem',
        '\t\t\treturn [view validateMenuItem:anItem];\n',
        '\t\t\treturn NO;\n'),
    # Find All still focuses the drawer field.
    'find-all-key-dropped': (
        'Sources/Preview/MyPDFKitView.m', '- (void)performPreviewFindTag:(NSInteger)tag',
        '    else if (tag == TSAdvancedFindActionFindAll)\n        [self focusDrawerSearchField];\n',
        ''),
    # The combined window's field editor is only for the Preview search fields.
    'any-client-in-combined': (
        'Sources/Preview/MyPDFKitView.m', '- (BOOL)isPreviewSearchClient:(id)client',
        '    if (![client isKindOfClass:[NSSearchField class]])\n        return NO;\n',
        '    return YES;\n'),
    # The drawer window's delegate must not be the Preview view.
    'drawer-delegate-is-view': (
        'Sources/Preview/MyPDFKitView.m', '- (void)attachDrawerFindFieldEditor',
        '        drawerWindow.delegate = self.drawerFieldEditorSource;\n',
        '        drawerWindow.delegate = self;\n'),
    # The small delegate must forward the field editor. Returning nil restores the ordinary editor.
    'drawer-source-returns-nil': (
        'Sources/Preview/MyPDFKitView.m',
        '- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client',
        '    return [self.owner windowWillReturnFieldEditor:sender toObject:client];\n',
        '    return nil;\n'),
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
open_at = drawer.find('NSDrawerOpenState')
open_return = drawer.find('return;', open_at)
open_branch = drawer[open_at:open_return] if open_at >= 0 and open_return > open_at else ''
expect('focusSearchField:' in open_branch, 'an open drawer does not focus its search field')
for signature in ('- (void)focusDrawerSearchField', '- (void)previewDrawerDidOpen:', '- (void)focusSearchField:'):
    body = method(kit, signature)
    for banned in ('doFind', 'findString', 'beginFind', 'performClick'):
        expect(banned not in body, f'{signature} runs a search ({banned})')

tags = method(kit, '- (void)performPreviewFindTag:')
show = tags.find('NSFindPanelActionShowFindPanel')
focus_toolbar = tags.find('focusPreviewToolbarSearchField')
nxt = tags.find('NSFindPanelActionNext')
again = tags.find('doFindAgain]')
prev = tags.find('NSFindPanelActionPrevious')
back = tags.find('doFindAgainBackwards')
find_all = tags.find('TSAdvancedFindActionFindAll')
focus_drawer = tags.find('focusDrawerSearchField')
expect(0 <= show < focus_toolbar < nxt < again < prev < back < find_all < focus_drawer,
       'Find, Find Next, Find Previous and Find All do not call their own commands')

preview = 'Sources/Windows/TSPreviewWindow.m'
preview_validate = method(preview, '- (BOOL)validateMenuItem:(NSMenuItem *)anItem')
find_validate = preview_validate[preview_validate.find('performFindPanelAction:'):]
expect('return [view validateMenuItem:anItem]' in find_validate and
       find_validate.find('return [view validateMenuItem:anItem]') < find_validate.find('return NO'),
       'the Preview window does not validate Find through the PDF view')
preview_perform = method(preview, '- (void)performFindPanelAction:')
expect('self.activeView' in preview_perform and 'self.myPDFKitView' in preview_perform and
       preview_perform.find('self.activeView') < preview_perform.find('self.myPDFKitView') and
       '[view performFindPanelAction:sender]' in preview_perform,
       'the Preview window does not forward Find to the active view, then the first view')

client = method(kit, '- (BOOL)isPreviewSearchClient:')
expect(client.count('return YES') == 1 and 'mySearchField' in client and 'myFullSearchField' in client and
       'owner->_searchField' in client and client.find('return YES') > client.find('mySearchField'),
       'the combined window uses the Preview field editor for something other than a Preview search field')
attach = method(kit, '- (void)attachDrawerFindFieldEditor')
expect('drawerWindow.delegate = self.drawerFieldEditorSource' in attach and
       'drawerWindow.delegate = self;' not in attach and
       'TSPreviewDrawerFieldEditorSource' in source(kit) and
       'windowWillReturnFieldEditor:' in source(kit),
       'the drawer window uses the Preview view as its delegate')
forwarder = method(kit, '- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client',
                   contains='self.owner')
expect('[self.owner windowWillReturnFieldEditor:sender toObject:client]' in forwarder and
       'return nil' not in forwarder,
       'the drawer field editor does not forward to the Preview view')
broken = method(kit, '- (void) breakConnections')
expect('drawerFieldEditorSource' in broken and 'delegate = nil' in broken,
       'closing the Preview leaves the drawer window delegate in place')

editor = method(kit, '- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client',
               contains='myPDFWindow')
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
