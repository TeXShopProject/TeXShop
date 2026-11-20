#!/usr/bin/env python3
"""The Previous Page and Next Page buttons of the image window turn the pages of its view.

Production toolbar code makes the two items (the helpers and the two branches of the toolbar delegate); the items go
to the toolbar controller, which passes the click to the image view, and their menu form keeps the title. Nothing is
shown on screen and no user settings are read. --mutations checks that the targets are needed."""
import os, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
toolbar = (root/'Sources/Windows/TSToolbarController.m').read_text()

fragments = []
def method(signature):
    fragment = production_method(toolbar, signature)
    fragments.append(('complete method:'+signature, toolbar, fragment))
    return fragment
def span(first, last):
    start = toolbar.index(first); end = toolbar.index(last, start) + len(last)
    fragment = toolbar[start:end]
    assert toolbar.count(fragment) == 1, first
    fragments.append(('statements:'+first, toolbar, fragment))
    return fragment

helpers = '\n'.join(method(s) for s in [
    '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey\n{',
    '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey imageName:',
    '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey image:',
    '- (NSToolbarItem*) makeToolbarSymbolsItemWithItemIdentifier:',
    '- (void)doPreviousPage:(id)sender',
    '- (void)doNextPage:(id)sender'])
branches = span('    if ([itemIdent isEqual: kPreviousPageButtonTID])', 'action:@selector(doNextPage:)];')

MUTATIONS = {
    # The earlier code: the action of the view, sent up the responder chain, which the helper turned into the controller.
    'responder-chain': ('target:self action:@selector(doPreviousPage:)];', 'target:nil action:@selector(previousPage:)];'),
    'controller-without-action': ('target:self action:@selector(doNextPage:)];', 'target:self action:@selector(nextPage:)];'),
}

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
BOOL atLeastMonterey = YES;
static NSString *kPreviousPageButtonTID = @"PreviousPageButton", *kNextPageButtonTID = @"NextPageButton";
@interface ImageView : NSView
@property NSInteger turns;
@end
@implementation ImageView
- (void)previousPage:(id)sender { self.turns -= 1; }
- (void)nextPage:(id)sender { self.turns += 1; }
@end
// The document of the image window: it does not turn pages (the responder chain ends here).
@interface Document : NSObject
@end
@implementation Document
@end
@interface Controller : NSObject
@property (strong) ImageView *pdfView;
- (NSToolbarItem *)item:(NSString *)itemIdent;
@end
@implementation Controller
HELPERS
- (NSToolbarItem *)item:(NSString *)itemIdent
{
BRANCHES
    return nil;
}
@end
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    Controller *controller = [Controller new]; controller.pdfView = [ImageView new];
    Document *document = [Document new];
    for (NSString *ident in @[kPreviousPageButtonTID, kNextPageButtonTID]) {
        NSToolbarItem *item = [controller item:ident];
        Check(item != nil && [item.itemIdentifier isEqual:ident], [@"the item is made: " stringByAppendingString:ident]);
        Check(item.image != nil, [@"the item has its arrow: " stringByAppendingString:ident]);
        Check(item.menuFormRepresentation.title.length > 0, [@"the menu form has a title: " stringByAppendingString:ident]);
        // Where a click goes: the item's target, else the responder chain up to the document.
        id receiver = item.target ?: ([document respondsToSelector:item.action] ? document : nil);
        Check(receiver != nil && [receiver respondsToSelector:item.action], [@"a click reaches something that turns pages: " stringByAppendingString:ident]);
        NSInteger before = controller.pdfView.turns;
        if ([receiver respondsToSelector:item.action]) [NSApp sendAction:item.action to:receiver from:item];
        NSInteger expected = before + ([ident isEqual:kPreviousPageButtonTID] ? -1 : 1);
        Check(controller.pdfView.turns == expected, [@"the image view turns the page: " stringByAppendingString:ident]);
    }
    if (!failures) puts("PASS: the page buttons of the image window turn the pages of the image view");
    return failures ? 1 : 0;
} }
'''

def run(program):
    with tempfile.TemporaryDirectory(prefix='texshop-image-page-buttons-') as temp:
        t = Path(temp)
        (t/'probe.m').write_text(program)
        build = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                                '-framework', 'Cocoa', str(t/'probe.m'), '-o', str(t/'probe')], capture_output=True, text=True)
        if build.returncode:
            return 2, build.stderr
        home = t/'Home'; (home/'Library/Preferences').mkdir(parents=True)
        result = subprocess.run([str(t/'probe')], capture_output=True, text=True, timeout=60,
                                env={**os.environ, 'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(t)})
        return result.returncode, result.stdout + result.stderr

program = PROGRAM.replace('HELPERS', helpers).replace('BRANCHES', branches)
verify_embedded(program, fragments)
if '--mutations' in sys.argv:
    for name, (old, new) in MUTATIONS.items():
        if old not in program:
            raise SystemExit(f'FAIL: mutation {name} does not apply')
        code, output = run(program.replace(old, new, 1))
        if code == 0:
            raise SystemExit(f'FAIL: mutation {name} was not detected')
        print('detected mutation', name)
code, output = run(program)
print(output.strip())
raise SystemExit(code)
