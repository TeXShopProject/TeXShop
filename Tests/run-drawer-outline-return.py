#!/usr/bin/env python3
"""Check that Return or Enter in the drawer's outline goes to the selected entry, as a click does (#61).

In the TSDocument nib of every language, the editable one and the compiled one, the drawer's outline is a
TSDrawerOutlineView. The class runs unchanged in an isolated harness, made by its name as a nib makes it, without
launching TeXShop. Key
events are sent to the outline view: Return and Enter with an entry selected send the outline's action, from the
outline view, with the entry chosen by the arrow keys or by typing; with no entry selected, with Command, Control or
Option held, and for other keys the event goes on to NSOutlineView. NSOutlineView's own keyDown: is replaced by a
recorder, so nothing beeps and no window is shown. In the nib of every language, the outline view itself must send
its action (takeDestinationFromOutline:) to the document's Preview window (pdfKitWindow of File's Owner), which
passes it to the part in use.
--mutation nib-no-class drops the class of the outline from the Base nib, no-enter the Enter key, any-modifier the
modifier check, nib-no-direct-action the outline's own action in the Base nib (the action of the cell inside it stays),
nib-other-window sends that action to the other TSPreviewWindow of the Base nib. The harness must then fail.
"""
import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path
from production_fragments import method, objc_class, verify_embedded
from source_tree import include_args, source_file

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['nib-no-class', 'no-enter', 'any-modifier', 'nib-no-direct-action', 'nib-other-window'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
klass = objc_class(source, 'TSDrawerOutlineView')
fragments = [('class: TSDrawerOutlineView', source, klass)]
if args.mutation == 'no-enter':
    old = ' || c == NSEnterCharacter'
    assert klass.count(old) == 1
    klass = klass.replace(old, '')
if args.mutation == 'any-modifier':
    old = 'if (modifiers == 0 && '
    assert klass.count(old) == 1
    klass = klass.replace(old, 'if (')

# The nib: the outline view in the drawer itself (not a cell inside it) sends takeDestinationFromOutline: to the
# Preview window (TSPreviewWindow). Return sends the outline view's own action, so its own connection is checked,
# in the Base nib and in the nib of every language.
import xml.etree.ElementTree as ElementTree
def check_nibs():
    nibs = sorted((root / 'Resources/Interfaces').glob('*.lproj/TSDocument.nib/designable.nib'))
    assert len(nibs) >= 12, 'TSDocument nibs not found'
    for nib in nibs:
        tree = ElementTree.parse(nib)
        if args.mutation == 'nib-no-direct-action' and nib.parent.parent.name == 'Base.lproj':
            # The outline loses its own action and keeps the one of the cell inside it.
            for outline_view in tree.iter('outlineView'):
                for connections in outline_view.findall('connections'):
                    for action in connections.findall('action'):
                        connections.remove(action)
        if args.mutation == 'nib-no-class' and nib.parent.parent.name == 'Base.lproj':
            for outline_view in tree.iter('outlineView'):
                outline_view.attrib.pop('customClass', None)
        if args.mutation == 'nib-other-window' and nib.parent.parent.name == 'Base.lproj':
            # The outline sends its own action to the other TSPreviewWindow of the nib; the cell inside it does not change.
            owner = next(o for o in tree.iter('customObject') if o.get('id') == '-2')
            preview = next(o.get('destination') for c in owner.findall('connections') for o in c.findall('outlet')
                           if o.get('property') == 'pdfKitWindow')
            other = next(w.get('id') for w in tree.iter('window')
                         if w.get('customClass') == 'TSPreviewWindow' and w.get('id') != preview)
            for outline_view in tree.iter('outlineView'):
                for connections in outline_view.findall('connections'):
                    for action in connections.findall('action'):
                        action.set('target', other)
        outline_views = [o for o in tree.iter('outlineView') if o.findall('tableColumns')]
        assert len(outline_views) == 1, f'{nib}: the drawer outline is not the one outline view'
        outline_view = outline_views[0]
        assert outline_view.get('customClass') == 'TSDrawerOutlineView', f'{nib}: the drawer outline is not a TSDrawerOutlineView'
        # The compiled nib, which the app loads, names the class too.
        compiled = sorted(nib.parent.glob('keyedobjects*.nib'))
        assert compiled and all(b'TSDrawerOutlineView' in c.read_bytes() for c in compiled), \
            f'{nib.parent}: the compiled nib does not name TSDrawerOutlineView; run Tests/compile-interface.py TSDocument'
        actions = [a for c in outline_view.findall('connections') for a in c.findall('action')]
        assert [a.get('selector') for a in actions] == ['takeDestinationFromOutline:'], \
            f'{nib}: the drawer outline itself does not send takeDestinationFromOutline:'
        # The target is the document's Preview window: the window File's Owner (TSDocument) has as pdfKitWindow,
        # which keeps the part in use. The nib has another TSPreviewWindow (pdfWindow), which is not it.
        owners = [o for o in tree.iter('customObject') if o.get('id') == '-2' and o.get('customClass') == 'TSDocument']
        assert len(owners) == 1, f'{nib}: File\'s Owner is not TSDocument'
        preview = [o.get('destination') for c in owners[0].findall('connections') for o in c.findall('outlet')
                   if o.get('property') == 'pdfKitWindow']
        assert len(preview) == 1, f'{nib}: File\'s Owner has no pdfKitWindow'
        windows = {w.get('id'): w for w in tree.iter('window')}
        assert windows.get(preview[0]) is not None and windows[preview[0]].get('customClass') == 'TSPreviewWindow', \
            f'{nib}: pdfKitWindow is not a TSPreviewWindow'
        assert actions[0].get('target') == preview[0], f'{nib}: the drawer outline does not send its action to pdfKitWindow'
    return nibs

if args.mutation in ('nib-no-class', 'nib-no-direct-action', 'nib-other-window'):
    try:
        check_nibs()
    except AssertionError as error:
        print(f'PASS: detected mutation {args.mutation}: {error}')
        raise SystemExit(0)
    raise SystemExit(f'mutation {args.mutation} was not detected')
nibs = check_nibs()
window = source_file(root, 'TSPreviewWindow.m').read_text(encoding='latin1')
assert '[(MyPDFKitView *)self.activeView takeDestinationFromOutline: sender];' in method(window, '- (IBAction) takeDestinationFromOutline: (id) sender'), \
    'the Preview window does not pass the outline action to the part in use'
print(f'PASS: in all {len(nibs)} nibs the drawer outline is a TSDrawerOutlineView and itself sends its action to the document Preview window (pdfKitWindow), which passes it to the part in use')

program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

CLASS

@interface Target : NSObject <NSOutlineViewDataSource>
@property NSInteger actions, row;
@property (weak) id sender;
@end
@implementation Target
- (void)takeDestinationFromOutline:(id)sender { self.actions++; self.sender = sender; self.row = [sender selectedRow]; }
- (NSInteger)outlineView:(NSOutlineView *)o numberOfChildrenOfItem:(id)item { return item ? 0 : 5; }
- (id)outlineView:(NSOutlineView *)o child:(NSInteger)i ofItem:(id)item { return [NSString stringWithFormat:@"%ld Chapter", (long)i + 1]; }
- (BOOL)outlineView:(NSOutlineView *)o isItemExpandable:(id)item { return NO; }
- (id)outlineView:(NSOutlineView *)o objectValueForTableColumn:(NSTableColumn *)c byItem:(id)item { return item; }
@end

static NSInteger passedOn = 0;
static void PassedOn(id self, SEL _cmd, NSEvent *event) { passedOn++; }

static NSEvent *Key(NSString *characters, unsigned short code, NSEventModifierFlags flags)
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0
                             context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code];
}
static void Check(BOOL ok, NSString *what) { if (!ok) { fprintf(stderr, "FAIL: %s\n", what.UTF8String); exit(1); } }

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    // NSOutlineView's own handling (a beep for Return) is replaced by a counter.
    class_replaceMethod([NSOutlineView class], @selector(keyDown:), (IMP)PassedOn, "v@:@");

    Target *target = [Target new];
    // A nib makes the outline by the class name it records.
    NSOutlineView *outline = [[NSClassFromString(@"TSDrawerOutlineView") alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    Check([outline class] == [TSDrawerOutlineView class], @"the class named in the nib exists");
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    [outline addTableColumn:column];
    [outline setOutlineTableColumn:column];
    [outline setDataSource:target];
    [outline setTarget:target];
    [outline setAction:@selector(takeDestinationFromOutline:)];
    [outline reloadData];
    Check([outline numberOfRows] == 5 && [outline selectedRow] == -1, @"no entry selected at first");

    // No entry selected: Return goes on to NSOutlineView.
    [outline keyDown:Key(@"\r", 36, 0)];
    Check(target.actions == 0 && passedOn == 1, @"Return with nothing selected goes on to NSOutlineView");

    // An entry chosen with the arrow keys (or by typing): Return and Enter go there.
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [outline keyDown:Key(@"\r", 36, 0)];
    Check(target.actions == 1 && target.row == 1 && target.sender == outline && passedOn == 1, @"Return goes to the selected entry");
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];
    unichar enter = NSEnterCharacter;
    [outline keyDown:Key([NSString stringWithCharacters:&enter length:1], 76, NSEventModifierFlagNumericPad)];
    Check(target.actions == 2 && target.row == 3 && passedOn == 1, @"Enter goes to the selected entry");
    [outline keyDown:Key(@"\r", 36, NSEventModifierFlagShift)];
    Check(target.actions == 3 && target.row == 3, @"Shift-Return goes to the selected entry too");

    // Command, Control and Option keep their meaning; other keys go on to NSOutlineView.
    NSEventModifierFlags modifiers[] = {NSEventModifierFlagCommand, NSEventModifierFlagControl, NSEventModifierFlagOption};
    for (int i = 0; i < 3; i++) {
        [outline keyDown:Key(@"\r", 36, modifiers[i])];
        Check(target.actions == 3 && passedOn == 2 + i, @"Return with Command, Control or Option goes on to NSOutlineView");
    }
    unichar down = NSDownArrowFunctionKey;
    [outline keyDown:Key([NSString stringWithCharacters:&down length:1], 125, NSEventModifierFlagNumericPad | NSEventModifierFlagFunction)];
    [outline keyDown:Key(@"2", 19, 0)];
    [outline keyDown:Key(@" ", 49, 0)];
    Check(target.actions == 3 && passedOn == 7, @"arrow keys, typed numbers and Space go on to NSOutlineView");

    // With no action (an outline without a target), Return goes on to NSOutlineView.
    [outline setAction:NULL];
    [outline keyDown:Key(@"\r", 36, 0)];
    Check(target.actions == 3 && passedOn == 8, @"Return without an action goes on to NSOutlineView");
    puts("PASS: Return and Enter in the drawer go to the selected entry; other keys and modified Return keep their meaning");
} return 0; }
'''
program = program.replace('CLASS', klass)
verify_embedded(program, fragments if not args.mutation else [])
with tempfile.TemporaryDirectory(prefix='texshop-drawer-return-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-mmacosx-version-min=14.6', '-w', '-fobjc-arc', '-framework', 'Cocoa',
                    *include_args(root), str(temp / 'test.m'), '-o', str(temp / 'test')], check=True)
    home = temp / 'home'
    (home / 'Library' / 'Preferences').mkdir(parents=True)
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temp))
    result = subprocess.run([str(temp / 'test')], timeout=120, env=environment, capture_output=True, text=True)
    print(result.stdout, end='')
    if args.mutation:
        assert result.returncode != 0, f'mutation {args.mutation} was not detected'
        print(f'PASS: detected mutation {args.mutation}: {result.stderr.strip()}')
    else:
        print(result.stderr, end='')
        result.check_returncode()
