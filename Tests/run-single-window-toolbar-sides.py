#!/usr/bin/env python3
"""The toolbar of the window that shows the source and the Preview follows the divider between them (#74).

On macOS 26 and later the source and the Preview of the single window run under the title bar and
the toolbar. AppKit blurs one scroll view in each part of the band, and parts the band only at a
divider that the toolbar follows (NSTrackingSeparatorToolbarItem). The toolbar of the single window
gets such an item right after the source's items: in its default set, and once in a toolbar saved
without it. Earlier systems keep the toolbar as it was. Parts of the Preview side by side start below
the band, in the single window as in the Preview window.

The production helpers and methods run unchanged in a stand-in document with real toolbars in an
off-screen window. Nothing is shown on screen and no user settings are read.
"""
import argparse, os, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args, source_file

MUTATIONS = {
    'no-default': ('    [withSides insertObject: skSidesTID atIndex: TSFullSplitSidesIndex(identifiers, [SUD boolForKey: SwitchSidesKey])];\n', ''),
    'spaces-right': ('    while (index > 0 && index < identifiers.count && [identifiers[index] isEqual: NSToolbarSpaceItemIdentifier])\n        index++;\n', ''),
    'swap-ignored': ('    if (previewOnLeft) {', '    if (NO) {'),
    'always': ('    return TSDocumentWindowsUseFullSizeContent();\n}', '    return YES;\n}'),
    'inserted-twice': ('    if ([identifiers containsObject: skSidesTID])\n        return;\n', ''),
    'other-divider': ('splitView: sides dividerIndex: 0]', 'splitView: [[NSSplitView alloc] init] dividerIndex: 0]'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toolbar = source_file(root, 'TSToolbarController.m').read_text()
document = source_file(root, 'TSDocument.m').read_text(encoding='latin1')

def fail(message):
    print('FAIL:', message, file=sys.stderr)
    sys.exit(1)

fragments = []
def method(source, signature):
    fragment = production_method(source, signature)
    fragments.append(('complete method:' + signature, source, fragment))
    return fragment
def span(source, first, last):
    start = source.index(first); end = source.index(last, start) + len(last)
    fragment = source[start:end]
    fragments.append(('statements:' + first, source, fragment))
    return fragment

# Where the production code calls these, checked in the production source.
move = production_method(document, '- (void) doMove: (id)sender;')
for call in ('[self keepSidesInFullSplitToolbar];', '[self.pdfKitWindow placeSplitViewForToolbar];'):
    if move.count(call) != 1 or not move.index(call) < move.index('[self.splitController showWindow: nil];'):
        fail('the single window gets ' + call + ' before it is shown')
for gone in ('placeFullSplitBelowToolbar', 'fullSplitPlacement', 'useSourceBorders'):
    if gone in document:
        fail('the sides of the single window are no longer placed below the band, nor the border of the source changed: ' + gone)
separate = production_method(document, '- (void) doSeparateWindows: (id)sender;')
release = separate.find('[self.pdfKitWindow releaseSplitViewPlacement];')
removal = separate.find('[self.pdfKitWindow.pdfKitSplitView removeFromSuperview];')
if release < 0 or not release < removal:
    fail('the Preview split view leaves its placement in the single window before it goes back to its own window')
setup = production_method(toolbar, '- (void) setupToolbar')
if not setup.index('[[self fullSplitWindow] setToolbar: [self makeToolbar: kFullWindowToolbarIdentifier]];') \
        < setup.index('[self keepSidesInFullSplitToolbar];'):
    fail('setupToolbar gives a saved toolbar of the single window the item once the toolbar is attached')
if 'skSidesTID' in production_method(toolbar, '- (NSArray *) toolbarAllowedItemIdentifiers:'):
    fail('the item is not offered in the customization sheet')

constants = span(toolbar, 'static NSString* \tkSourceToolbarIdentifier', 'kHtmlSearchTID              = @"HtmlSearch";')
sides = span(toolbar, 'static BOOL TSFullSplitToolbarFollowsSides(void)', '    return index;\n}')
item_for = production_method(toolbar, '- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier:')
branch = span(toolbar, '    if ([itemIdent isEqual: skSidesTID]) {', 'splitView: sides dividerIndex: 0];\n    }\n')
if item_for.count(branch) != 1:
    fail('itemForItemIdentifier makes the item')
methods = '\n'.join(method(toolbar, s) for s in (
    '- (NSArray *) toolbarDefaultItemIdentifiers:', '- (void) keepSidesInFullSplitToolbar',
    '- (NSArray *) defaultItemIdentifiersOfToolbar:'))

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewLayout.h"
#import "TSPreviewAppearance.h"
#define MITSU_PDF 1
static NSUserDefaults *defaults;
#define SUD defaults
static NSString *SwitchSidesKey = @"SwitchSides";
static BOOL fullSize = YES;
static BOOL TSDocumentWindowsUseFullSizeContent(void) { return fullSize; }
CONSTANTS
SIDES
@interface TSDocument : NSObject <NSToolbarDelegate> { @public NSView *leftView; NSWindow *window; }
@end
@implementation TSDocument
- (BOOL)sharingExists { return YES; }
- (NSWindow *)fullSplitWindow { return window; }
METHODS
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)inserted
{
BRANCH    return [[NSToolbarItem alloc] initWithItemIdentifier:itemIdent];
}
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return [self toolbarDefaultItemIdentifiers:toolbar]; }
@end
static int checks;
static void check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
static NSUInteger count(NSArray *list, NSString *ident) { return [list indexesOfObjectsPassingTest:^BOOL(id o, NSUInteger i, BOOL *s) { return [o isEqual:ident]; }].count; }
static NSArray *identifiers(NSToolbar *bar) { return [bar.items valueForKey:@"itemIdentifier"]; }
int main(void) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"org.texshop.test.sides.%d", getpid()]];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1500, 600)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
        NSSplitView *split = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
        split.vertical = YES;
        NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 700, 600)], *right = [[NSView alloc] initWithFrame:NSMakeRect(709, 0, 791, 600)];
        [split addSubview:left]; [split addSubview:right]; [w.contentView addSubview:split];
        TSDocument *d = [TSDocument new];
        d->leftView = left; d->window = w;

        // Where the item goes in a list of items.
        NSArray *source = @[skTypesetTID, skProgramTID, kSplitID, NSToolbarSpaceItemIdentifier, NSToolbarSpaceItemIdentifier, kPreviousPageButtonKKTID, NSToolbarFlexibleSpaceItemIdentifier, skSearchTID];
        check(TSFullSplitSidesIndex(source, NO) == 5, @"after the source's items and the spaces that follow them");
        NSArray *swapped = @[kPreviousPageButtonKKTID, skSearchTID, NSToolbarSpaceItemIdentifier, skTypesetTID, skMacrosTID, kSplitID];
        check(TSFullSplitSidesIndex(swapped, YES) == 3, @"with the Preview on the left, before the first of the source's items");
        check(TSFullSplitSidesIndex(@[kPreviousPageButtonKKTID, skSearchTID], NO) == 0, @"without items of the source, at the start");
        check(TSFullSplitSidesIndex(@[kPreviousPageButtonKKTID, skSearchTID], YES) == 2, @"without items of the source and the Preview on the left, at the end");
        check(TSFullSplitSidesIndex(@[skTypesetTID, kPreviousPageButtonKKTID, skMacrosTID, NSToolbarSpaceItemIdentifier], NO) == 4, @"after the last item of the source");

        // The default sets.
        NSToolbar *full = [[NSToolbar alloc] initWithIdentifier:kFullWindowToolbarIdentifier];
        NSToolbar *preview = [[NSToolbar alloc] initWithIdentifier:kPDFKitToolbarIdentifier];
        for (NSNumber *switched in @[@NO, @YES]) {
            [defaults setBool:switched.boolValue forKey:SwitchSidesKey];
            NSArray *standard = [d toolbarDefaultItemIdentifiers:full];
            check(count(standard, skSidesTID) == 1, @"the single window's default set follows the divider once");
            NSUInteger at = [standard indexOfObject:skSidesTID];
            if (switched.boolValue)
                check([standard[at + 1] isEqual:skTypesetTID] && [standard[at - 1] isEqual:NSToolbarSpaceItemIdentifier], @"with the Preview on the left the source's items follow the divider");
            else
                check([standard[at - 1] isEqual:NSToolbarSpaceItemIdentifier] && [standard[at + 1] isEqual:kPreviousPageButtonKKTID], @"the Preview's items follow the divider");
            check(count([d toolbarDefaultItemIdentifiers:preview], skSidesTID) == 0, @"the Preview window's toolbar does not follow it");
        }
        [defaults setBool:NO forKey:SwitchSidesKey];
        fullSize = NO;
        check(count([d toolbarDefaultItemIdentifiers:full], skSidesTID) == 0, @"before macOS 26 the default set is as it was");
        check([d toolbar:full itemForItemIdentifier:skSidesTID willBeInsertedIntoToolbar:YES] == nil, @"before macOS 26 there is no such item");
        fullSize = YES;

        // The item follows the divider between the two sides.
        NSToolbarItem *item = [d toolbar:full itemForItemIdentifier:skSidesTID willBeInsertedIntoToolbar:YES];
        check([item isKindOfClass:[NSTrackingSeparatorToolbarItem class]], @"the item follows a divider");
        NSTrackingSeparatorToolbarItem *separator = (NSTrackingSeparatorToolbarItem *)item;
        check(separator.splitView == split && separator.dividerIndex == 0, @"the divider between the source and the Preview");

        // A toolbar saved without the item gets it once, at its place.
        NSToolbar *saved = [[NSToolbar alloc] initWithIdentifier:[NSString stringWithFormat:@"saved-%d", getpid()]];
        saved.delegate = d;
        w.toolbar = saved;
        for (NSString *ident in source)
            [saved insertItemWithItemIdentifier:ident atIndex:saved.items.count];
        fullSize = NO;
        [d keepSidesInFullSplitToolbar];
        check(count(identifiers(saved), skSidesTID) == 0, @"before macOS 26 a saved toolbar stays as it was");
        fullSize = YES;
        [d keepSidesInFullSplitToolbar];
        check(count(identifiers(saved), skSidesTID) == 1 && [identifiers(saved) indexOfObject:skSidesTID] == 5, @"a saved toolbar gets the item after the source's items");
        [d keepSidesInFullSplitToolbar];
        check(count(identifiers(saved), skSidesTID) == 1, @"and only once");
        [saved removeItemAtIndex:[identifiers(saved) indexOfObject:skSidesTID]];
        [d keepSidesInFullSplitToolbar];
        check(count(identifiers(saved), skSidesTID) == 1, @"a toolbar that lost the item gets it back");
        [defaults removePersistentDomainForName:[NSString stringWithFormat:@"org.texshop.test.sides.%d", getpid()]];
        printf("%d checks\n", checks);
    }
    return 0;
}
'''
program = program.replace('CONSTANTS', constants).replace('SIDES', sides).replace('METHODS', methods).replace('BRANCH', branch)
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert program.count(old) == 1, args.mutation
    program = program.replace(old, new)
else:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='texshop-single-sides-') as directory:
    source = Path(directory) / 'test.m'
    source.write_text(program)
    binary = Path(directory) / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I' + str(root / 'Tests'),
                    '-framework', 'Cocoa', str(source), '-o', str(binary)], check=True)
    home = Path(directory) / 'home'; (home / 'Library/Preferences').mkdir(parents=True)
    subprocess.run([str(binary)], check=True, timeout=60, env={**os.environ, 'CFFIXED_USER_HOME': str(home)})
print('PASS run-single-window-toolbar-sides')
