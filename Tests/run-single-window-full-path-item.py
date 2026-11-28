#!/usr/bin/env python3
"""Show Full Path in the toolbar of the window that shows the source and the Preview.

The single window has a toolbar of its own, and a view can be in one toolbar at a time, so the item
of the single window (ShowFullPathSplit) has a button of its own, made like the source window's and
with the same labels. It belongs to the source's side of the toolbar. Turning the switch puts both
buttons, and the menus of both items (shown when the toolbar is too narrow), in the same state.

The production methods run unchanged in a stand-in document with real toolbars of off-screen
windows. Nothing is shown on screen and no user settings are read.
"""
import argparse, re, subprocess, sys, tempfile
from pathlib import Path
from source_tree import source_file

MUTATIONS = {
    'not-allowed': ('TSToolbarController.m', '                    skAutoCompleteID,\n                    skShowFullPathID,\n', '                    skAutoCompleteID,\n'),
    'not-allowed-without-sharing': ('TSToolbarController.m', ' \t\t\t\t\tskAutoCompleteID,\n                    skShowFullPathID,\n', ' \t\t\t\t\tskAutoCompleteID,\n'),
    'preview-side': ('TSToolbarController.m', 'kSplitID, skAutoCompleteID, skShowFullPathID, nil]', 'kSplitID, skAutoCompleteID, nil]'),
    'shares-source-button': ('TSToolbarController.m', 'customView:[self showFullPathSplitButton]]', 'customView:showFullPathButton]'),
    'own-labels': ('TSToolbarController.m', 'key:kShowFullPathID\n\t\t\t\t\t\t\t\t\t\t\t\t   customView:[self showFullPathSplitButton]]',
                   'key:itemIdent\n\t\t\t\t\t\t\t\t\t\t\t\t   customView:[self showFullPathSplitButton]]'),
    'split-button-not-updated': ('TSDocument.m', '\t[self.fullPathSplitButton setState: showFullPath];\n', ''),
    'split-menu-not-updated': ('TSDocument.m', '\t[items addObjectsFromArray: [[fullSplitWindow toolbar] items] ?: @[]];\n', ''),
    'split-button-other-action': ('TSDocument.m', 'target: self action: @selector(changeShowFullPath:)]', 'target: self action: @selector(changeAutoComplete:)]'),
    'split-button-starts-off': ('TSDocument.m', '\t\t[button setState: showFullPath ? NSControlStateValueOn : NSControlStateValueOff];\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = {name: source_file(root, name).read_text(encoding='latin1') for name in ('TSToolbarController.m', 'TSDocument.m')}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert text[name].count(old) == 1, args.mutation
    text[name] = text[name].replace(old, new)

checks = 0
def check(ok, message):
    global checks
    checks += 1
    if not ok:
        print('FAIL:', message, file=sys.stderr)
        sys.exit(1)

def method(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start) + 3]

toolbar = text['TSToolbarController.m']
check('static NSString*\tskShowFullPathID\t = @"ShowFullPathSplit";' in toolbar, 'the single window has an item of its own')
allowed = method(toolbar, '- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar')
full = allowed[allowed.index('if ([toolbarID isEqual:kFullWindowToolbarIdentifier])'):allowed.index('if ([toolbarID isEqual:kHtmlWindowToolbarIdentifier])')]
lists = re.findall(r'arrayWithObjects:(.*?)nil\]', full, flags=re.S)
check(len(lists) == 2 and all('skShowFullPathID' in l and 'kShowFullPathID,' not in l.replace('skShowFullPathID', '') for l in lists),
      'the single window may have the item, with and without sharing, and not the source window\'s item')
source_items = method(toolbar, 'static NSSet<NSString *> *TSFullSplitSourceItems(void)')
check('skShowFullPathID' in source_items, 'the item stays on the source\'s side of the divider')
item = toolbar[toolbar.index('if ([itemIdent isEqual: skShowFullPathID])'):]
item = item[:item.index('return toolbarItem;')]
check('key:kShowFullPathID' in item and 'customView:[self showFullPathSplitButton]' in item,
      'the item has the labels of the source window\'s item and a button of its own')
check('@selector(changeShowFullPath:)' in item, 'the menu of the item turns the switch')
default = method(toolbar, '- (NSArray *) defaultItemIdentifiersOfToolbar') if '- (NSArray *) defaultItemIdentifiersOfToolbar' in toolbar else ''
check('skShowFullPathID' not in default, 'the default set is unchanged')

document = text['TSDocument.m']
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
@interface TestDocument : NSObject <NSToolbarDelegate> {
@public
    NSButton *showFullPathButton;
    BOOL showFullPath;
    NSWindow *textWindow, *fullSplitWindow;
}
@property (strong) NSButton *fullPathSplitButton;
@property int changes;
@end
@implementation TestDocument
- (void) changeShowFullPath: sender { self.changes++; }
- (void) changeAutoComplete: sender {}
''' + method(document, '- (NSButton *) showFullPathSplitButton') + method(document, '- (void) fixShowFullPathButton\n{') + r'''
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.view = [identifier isEqual:@"ShowFullPath"] ? showFullPathButton : [self showFullPathSplitButton];
    NSMenuItem *form = [NSMenuItem new];
    form.submenu = [NSMenu new];
    [form.submenu addItemWithTitle:@"Show Full Path" action:@selector(changeShowFullPath:) keyEquivalent:@""];
    item.menuFormRepresentation = form;
    return item;
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[@"ShowFullPath", @"ShowFullPathSplit"]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[[toolbar.identifier isEqual:@"source"] ? @"ShowFullPath" : @"ShowFullPathSplit"];
}
@end
static int checks;
static void check(BOOL ok, const char *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } }
static NSWindow *window(void) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    w.releasedWhenClosed = NO;
    return w;
}
static NSControlStateValue menuState(NSWindow *w) {
    return [w.toolbar.items.firstObject.menuFormRepresentation.submenu itemAtIndex:0].state;
}
int main(void) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        TestDocument *d = [TestDocument new];
        d->showFullPathButton = [NSButton checkboxWithTitle:@"フルパス表示" target:d action:@selector(changeShowFullPath:)];
        d->showFullPathButton.font = [NSFont systemFontOfSize:11];
        [d->showFullPathButton setFrameSize:NSMakeSize(100, 18)];
        d->showFullPath = YES;
        d->textWindow = window();
        d->fullSplitWindow = window();
        for (NSWindow *w in @[d->textWindow, d->fullSplitWindow]) {
            NSToolbar *t = [[NSToolbar alloc] initWithIdentifier: w == d->textWindow ? @"source" : @"single"];
            t.delegate = d;
            w.toolbar = t;
        }
        NSButton *split = [d showFullPathSplitButton];
        check(split != d->showFullPathButton && [d showFullPathSplitButton] == split, "the single window has one button of its own");
        check([split.title isEqual:@"フルパス表示"] && [split.font isEqual:d->showFullPathButton.font]
              && NSEqualSizes(split.frame.size, d->showFullPathButton.frame.size), "the button looks like the source window's");
        check(split.state == NSControlStateValueOn, "the button starts in the state of the switch");
        [split performClick:nil];
        check(d.changes == 1, "the button turns the switch");
        check(d->fullSplitWindow.toolbar.items.firstObject.view == split && d->textWindow.toolbar.items.firstObject.view == d->showFullPathButton,
              "each toolbar shows its own button");
        for (int i = 0; i < 2; i++) {
            BOOL on = (i == 1);
            d->showFullPath = on;
            [d fixShowFullPathButton];
            NSControlStateValue state = on ? NSControlStateValueOn : NSControlStateValueOff;
            check(d->showFullPathButton.state == state && split.state == state, "both buttons follow the switch");
            check(menuState(d->textWindow) == state && menuState(d->fullSplitWindow) == state, "the menus of both items follow the switch");
        }
        d->textWindow.toolbar = nil;
        d->showFullPath = YES;
        [d fixShowFullPathButton];
        check(menuState(d->fullSplitWindow) == NSControlStateValueOn, "the single window's menu follows without a source toolbar");
        printf("%d\n", checks);
    }
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='texshop-single-full-path-') as directory:
    source = Path(directory) / 'test.m'
    source.write_text(program)
    binary = Path(directory) / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-objc-property-no-attribute',
                    '-framework', 'Cocoa', '-I', str(root / 'Tests'), str(source), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        print(result.stderr, end='', file=sys.stderr)
        sys.exit(1)
    checks += int(result.stdout.strip())
print(f'PASS run-single-window-full-path-item ({checks} checks)')
