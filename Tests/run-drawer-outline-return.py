#!/usr/bin/env python3
"""Check that Return or Enter in the drawer's outline goes to the selected entry, as a click does (#61).

The nib makes the drawer's outline a plain NSOutlineView; setupOutline turns it into TSDrawerOutlineView. The class
and setupOutline run unchanged in an isolated harness with a real NSOutlineView, without launching TeXShop. Key
events are sent to the outline view: Return and Enter with an entry selected send the outline's action, from the
outline view, with the entry chosen by the arrow keys or by typing; with no entry selected, with Command, Control or
Option held, and for other keys the event goes on to NSOutlineView. NSOutlineView's own keyDown: is replaced by a
recorder, so nothing beeps and no window is shown. The Base nib must still send the outline's action
(takeDestinationFromOutline:) to the Preview window, which passes it to the part in use.
--mutation no-swap drops the class change from setupOutline, no-enter the Enter key, any-modifier the modifier
check. The harness must then fail.
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
parser.add_argument('--mutation', choices=['no-swap', 'no-enter', 'any-modifier'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
klass = objc_class(source, 'TSDrawerOutlineView')
setup = method(source, '- (void) setupOutline')
fragments = [('class: TSDrawerOutlineView', source, klass), ('complete method: - (void) setupOutline', source, setup)]
if args.mutation == 'no-swap':
    old = '\t\tobject_setClass(_outlineView, [TSDrawerOutlineView class]);\n'
    assert setup.count(old) == 1
    setup = setup.replace(old, '\t\t;\n')
if args.mutation == 'no-enter':
    old = ' || c == NSEnterCharacter'
    assert klass.count(old) == 1
    klass = klass.replace(old, '')
if args.mutation == 'any-modifier':
    old = 'if (modifiers == 0 && '
    assert klass.count(old) == 1
    klass = klass.replace(old, 'if (')

# The nib: the outline view in the drawer sends takeDestinationFromOutline: to the Preview window (TSPreviewWindow).
nib = (root / 'Resources/Interfaces/Base.lproj/TSDocument.nib/designable.nib').read_text(encoding='utf-8')
outline = re.search(r'<outlineView [^>]*id="763">.*?</outlineView>', nib, re.S).group(0)
assert 'customClass' not in outline.split('>', 1)[0], 'the drawer outline has a class in the nib; check setupOutline'
action = re.findall(r'<action selector="takeDestinationFromOutline:" target="(\d+)"', outline)
assert action, 'the drawer outline no longer sends takeDestinationFromOutline:'
for target in set(action):
    assert re.search(r'<window [^>]*id="%s"[^>]*customClass="TSPreviewWindow"' % target, nib), 'action target is not the Preview window'
window = source_file(root, 'TSPreviewWindow.m').read_text(encoding='latin1')
assert '[(MyPDFKitView *)self.activeView takeDestinationFromOutline: sender];' in method(window, '- (IBAction) takeDestinationFromOutline: (id) sender'), \
    'the Preview window does not pass the outline action to the part in use'
print('PASS: the Base nib sends the drawer outline action to the Preview window, which passes it to the part in use')

program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#define SUD [NSUserDefaults standardUserDefaults]
NSString *UseOutlineKey = @"UseOutline";

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

// setupOutline also asks the PDF for its outline and keeps the open entries; stand-ins keep it isolated.
@interface TSOutlineExpansion : NSObject
- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView;
- (void)reloadOutline;
@end
@implementation TSOutlineExpansion
- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView { return [super init]; }
- (void)reloadOutline {}
@end
@interface NSObject (OutlineRoot)
- (id)outlineRoot;
@end

@interface FirstPart : NSObject
{
    NSOutlineView *_outlineView;
}
@property (strong) TSOutlineExpansion *outlineExpansion;
@property (strong) id outline;
- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView;
- (id)document;
- (void)setupOutline;
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
    [SUD setBool:YES forKey:UseOutlineKey];

    Target *target = [Target new];
    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    [outline addTableColumn:column];
    [outline setOutlineTableColumn:column];
    [outline setDataSource:target];
    [outline setTarget:target];
    [outline setAction:@selector(takeDestinationFromOutline:)];
    [outline reloadData];
    Check([outline class] == [NSOutlineView class], @"the nib's outline starts as NSOutlineView");

    FirstPart *part = [[FirstPart alloc] initWithOutlineView:outline];
    [part setupOutline];
    Check([outline class] == [TSDrawerOutlineView class], @"setupOutline makes the drawer outline answer Return");
    [part setupOutline];
    Check([outline class] == [TSDrawerOutlineView class], @"a second setupOutline keeps the class");
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

@implementation FirstPart
- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView { if ((self = [super init])) _outlineView = outlineView; return self; }
- (id)document { return nil; }
SETUP
@end
'''
# setupOutline asks [[self document] outlineRoot] and builds the expansion object; stand-ins keep it isolated.
program = program.replace('CLASS', klass).replace('SETUP', setup)
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
