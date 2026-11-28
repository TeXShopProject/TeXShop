#!/usr/bin/env python3
"""Settings > General > Window > Source position in the combined window: open combined windows change
sides at once.

The production method of TSDocument runs unchanged in a stand-in document with real views in an
off-screen window: the source and the Preview move to their sides, the source keeps its width (unless a
side is collapsed), the status bar stays below the source, the toolbar items follow the sides, the
Preview is placed below the band again, and the view with the keyboard keeps it. A window that is not
combined, or whose sides are already right, is left alone. The Settings action asks every open document.
Nothing is shown on screen and no user settings are read.
"""
import argparse, os, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args, source_file

MUTATIONS = {
    'not-combined-too': ('    if (! useFullSplitWindow || fullSplitWindow == nil)\n        return;\n', ''),
    'width-lost': ('        [sides setPosition: round(interchange ? shared - sourceWidth : sourceWidth) ofDividerAtIndex: 0];\n', ''),
    'collapsed-forced': ('        && ! [sides isSubviewCollapsed: leftView] && ! [sides isSubviewCollapsed: rightView]', ''),
    'toolbar-stays': ('    [self keepSidesInFullSplitToolbar];\n    [self.pdfKitWindow placeSplitViewForToolbar];\n', '    [self.pdfKitWindow placeSplitViewForToolbar];\n'),
    'focus-lost': ('        [fullSplitWindow makeFirstResponder: focus];\n', ''),
    'status-bar-left': ('    [self.sourceStatusBar placeBelowView: splitView];\n    [previewSide', '    [previewSide'),
    'redone-each-time': ('    if (splitView.superview == sourceSide || preview == nil)\n        return;\n', '    if (preview == nil)\n        return;\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
document = source_file(root, 'TSDocument.m').read_text(encoding='latin1')
preferences = source_file(root, 'TSPreferences.m').read_text(encoding='utf-8')

def fail(message):
    print('FAIL:', message, file=sys.stderr)
    sys.exit(1)

follow = production_method(document, '- (void) followSourceSideInFullSplitWindow')
fragments = [('complete method:followSourceSideInFullSplitWindow', document, follow)]
action = production_method(preferences, '- (IBAction)sourceOnLeftChanged:sender')
if '[SUD setBool:result forKey:SwitchSidesKey];' not in action \
        or 'NSDocumentController.sharedDocumentController.documents' not in action \
        or '[(TSDocument *)document followSourceSideInFullSplitWindow];' not in action \
        or not action.index('setBool:result forKey:SwitchSidesKey') < action.index('followSourceSideInFullSplitWindow'):
    fail('the Settings action stores the side, then asks every open document to follow it')
if '- (void) followSourceSideInFullSplitWindow;' not in source_file(root, 'TSDocument.h').read_text(encoding='latin1'):
    fail('TSDocument declares followSourceSideInFullSplitWindow')

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
static NSUserDefaults *defaults;
#define SUD defaults
static NSString *SwitchSidesKey = @"SwitchSides";
static int releases, placements, toolbarFollows, annotationFollows;
@interface FakePreviewWindow : NSObject
@property NSView *pdfKitSplitView;
@end
@implementation FakePreviewWindow
- (void)releaseSplitViewPlacement { releases++; }
- (void)placeSplitViewForToolbar { placements++; }
@end
@interface FakeStatusBar : NSView
@property NSView *below;
@end
@implementation FakeStatusBar
- (void)placeBelowView:(NSView *)view { self.below = view; }
@end
@interface TSDocument : NSObject { @public BOOL useFullSplitWindow; NSWindow *fullSplitWindow; NSView *leftView, *rightView, *splitView; }
@property FakePreviewWindow *pdfKitWindow;
@property FakeStatusBar *sourceStatusBar;
@end
@implementation TSDocument
- (void)keepSidesInFullSplitToolbar { toolbarFollows++; }
- (void)annotationBarFollowWindowChange { annotationFollows++; }
FOLLOW
@end
@interface Collapsing : NSObject <NSSplitViewDelegate>
@end
@implementation Collapsing
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview { return YES; }
@end
static int checks;
static void check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
int main(void) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *suite = [NSString stringWithFormat:@"org.texshop.test.switch-sides.%d", getpid()];
        defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1500, 600)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        NSSplitView *sides = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
        sides.vertical = YES;
        NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 600)], *right = [[NSView alloc] initWithFrame:NSMakeRect(510, 0, 990, 600)];
        [sides addSubview:left]; [sides addSubview:right]; [w.contentView addSubview:sides];
        [sides adjustSubviews];
        [sides setPosition:500 ofDividerAtIndex:0];
        NSView *source = [[NSView alloc] initWithFrame:left.bounds];
        NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
        [source addSubview:text];
        NSView *pdf = [[NSView alloc] initWithFrame:right.bounds];
        [left addSubview:source]; [right addSubview:pdf];
        TSDocument *d = [TSDocument new];
        d->fullSplitWindow = w; d->leftView = left; d->rightView = right; d->splitView = source;
        d.pdfKitWindow = [FakePreviewWindow new]; d.pdfKitWindow.pdfKitSplitView = pdf;
        d.sourceStatusBar = [FakeStatusBar new];
        [w makeFirstResponder:text];
        CGFloat shared = NSWidth(sides.bounds) - sides.dividerThickness;
        CGFloat width = NSWidth(left.frame);

        // Not combined: nothing moves.
        [defaults setBool:YES forKey:SwitchSidesKey];
        d->useFullSplitWindow = NO;
        [d followSourceSideInFullSplitWindow];
        check(source.superview == left && pdf.superview == right && releases == 0 && toolbarFollows == 0, @"a window that is not combined is left alone");

        // Combined: the source goes right, the Preview left.
        d->useFullSplitWindow = YES;
        [d followSourceSideInFullSplitWindow];
        check(source.superview == right && pdf.superview == left, @"the source and the Preview change sides at once");
        check(NSEqualRects(pdf.frame, left.bounds), @"the Preview fills its side");
        check(d.sourceStatusBar.below == source, @"the status bar stays below the source");
        check(fabs(NSWidth(right.frame) - width) <= 1, [NSString stringWithFormat:@"the source keeps its width: %.0f, was %.0f", NSWidth(right.frame), width]);
        check(fabs(NSWidth(left.frame) - (shared - width)) <= 1, @"the Preview keeps its width");
        check(releases == 1 && placements == 1 && toolbarFollows == 1 && annotationFollows == 1, @"the toolbar items follow, the Preview is placed below the band again, the annotation bar follows");
        check(w.firstResponder == text, @"the source keeps the keyboard");
        [d followSourceSideInFullSplitWindow];
        check(source.superview == right && releases == 1 && toolbarFollows == 1, @"a window whose sides are right is left alone");

        // Back to the left.
        [defaults setBool:NO forKey:SwitchSidesKey];
        [d followSourceSideInFullSplitWindow];
        check(source.superview == left && pdf.superview == right && fabs(NSWidth(left.frame) - width) <= 1, @"back on the left, with its width");
        check(toolbarFollows == 2 && w.firstResponder == text, @"the toolbar follows again and the source keeps the keyboard");

        // A collapsed Preview: the divider is not set.
        Collapsing *collapsing = [Collapsing new];
        sides.delegate = collapsing;
        [sides setPosition:NSWidth(sides.bounds) ofDividerAtIndex:0];
        check([sides isSubviewCollapsed:right], @"(the Preview is collapsed)");
        [defaults setBool:YES forKey:SwitchSidesKey];
        [d followSourceSideInFullSplitWindow];
        check(source.superview == right && [sides isSubviewCollapsed:right], @"with a collapsed side the divider stays where it is");
        [defaults removePersistentDomainForName:suite];
        printf("%d checks\n", checks);
    }
    return 0;
}
'''
program = program.replace('FOLLOW', follow)
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert program.count(old) == 1, args.mutation
    program = program.replace(old, new)
else:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='texshop-switch-sides-') as directory:
    source = Path(directory) / 'test.m'
    source.write_text(program)
    binary = Path(directory) / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I' + str(root / 'Tests'),
                    '-framework', 'Cocoa', str(source), '-o', str(binary)], check=True)
    home = Path(directory) / 'home'; (home / 'Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(binary)], timeout=60, env={**os.environ, 'CFFIXED_USER_HOME': str(home)})
    if result.returncode:
        sys.exit(1)
print('PASS run-single-window-switch-sides')
