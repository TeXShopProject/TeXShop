#!/usr/bin/env python3
"""Preview parts side by side start below the toolbar (macOS 26 and later).

In a window whose content runs under the title bar and the toolbar, each part of the
Preview brings its own band under the toolbar; side by side, AppKit blurs only one of
them and the divider runs up through the toolbar. The production placeSplitViewForToolbar
and releaseSplitViewPlacement of TSPreviewWindow run in a window with a toolbar and a
full-size content view that is never ordered on screen. The test checks:

- parts side by side: the split view starts at the bottom of the band under the toolbar,
  so the divider ends there, and keeps reaching 2 points below the bottom edge;
- the split view follows the band when it changes height: a title bar accessory such as
  the annotation toolbar, a hidden toolbar, a window of another size;
- one part, and parts one above the other, run under the toolbar as before; unsplitting
  gives the split view back its frame, 2 points below the bottom edge included;
- a window whose content does not run under the toolbar (before macOS 26) is left as it was;
- a split view in another window, as in the combined window, is left to that window;
- the production call sites: mainSplitPdfKitWindow places the split view when it splits
  and when it unsplits; moving the Preview into the combined window hands the split view
  back first, and moving it back places it again.
"""
import argparse, os, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file
from production_fragments import method, verify_embedded

MUTATIONS = {
    # The parts side by side start at the top of the window, under the toolbar.
    'side-under-toolbar': ('place', '[split.topAnchor constraintEqualToAnchor: content.safeAreaLayoutGuide.topAnchor]',
                           '[split.topAnchor constraintEqualToAnchor: content.topAnchor]'),
    # Parts one above the other also start below the toolbar.
    'stacked-below': ('place', '        self.windowIsSplit && split.isVertical;', '        self.windowIsSplit;'),
    # A window whose content does not run under the toolbar gets the placement too.
    'any-window': ('place', ' && (self.styleMask & NSWindowStyleMaskFullSizeContentView) &&\n', ' &&\n'),
    # The split view keeps the size it had below the toolbar after unsplitting.
    'frame-not-given-back': ('release', '    [self fitSplitViewToContent];\n', ''),
    # The split view gets the content view's bounds back, without its 2 points below the bottom edge.
    'outsets-lost': ('release', '    NSEdgeInsets outsets = self.splitViewOutsets;\n    split.frame', '    NSEdgeInsets outsets = NSEdgeInsetsMake(0, 0, 0, 0);\n    split.frame'),
    # Back from the combined window, the split view keeps the content view's bounds.
    'roundtrip-bounds': ('document', '            [self.pdfKitWindow fitSplitViewToContent];\n', '            [self.pdfKitWindow.pdfKitSplitView setFrame: [[self.pdfKitWindow contentView] bounds]];\n'),
    # Below the toolbar the split view ends at the bottom edge of the window.
    'bottom-outset-lost': ('place', 'constraintEqualToAnchor: content.bottomAnchor constant: outsets.bottom]', 'constraintEqualToAnchor: content.bottomAnchor]'),
    # A split view in another window is placed against the Preview window's content view.
    'other-window': ('place', 'split != nil && split.superview == content && ', 'split != nil && '),
    # Splitting leaves the split view where it is.
    'split-not-placed': ('main', '        // Side by side, the parts start below the toolbar before they are given their pages.\n        [self placeSplitViewForToolbar];\n', ''),
    # Unsplitting leaves the split view below the toolbar.
    'unsplit-not-placed': ('main', '        // The part that stays runs under the toolbar again.\n        [self placeSplitViewForToolbar];\n', ''),
    # Moving into the combined window keeps the constraints of the Preview window.
    'move-not-released': ('document', '            [self.pdfKitWindow releaseSplitViewPlacement];\n', ''),
    # Moving back leaves the parts side by side under the toolbar.
    'back-not-placed': ('document', '            [self.pdfKitWindow fitSplitViewToContent];\n            [self.pdfKitWindow placeSplitViewForToolbar];\n', '            [self.pdfKitWindow fitSplitViewToContent];\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

def read(name):
    return source_file(root, name).read_text(encoding='latin1')
window_source = read('TSPreviewWindow.m')
document_source = read('TSDocument.m')
place = method(window_source, '- (void) placeSplitViewForToolbar')
release = '\n\n'.join(method(window_source, m) for m in ('- (void) takeSplitViewOutsets', '- (void) fitSplitViewToContent', '- (void) releaseSplitViewPlacement'))
main = method(window_source, '- (void) mainSplitPdfKitWindow\n{\n    NSSize        theSize, newSize1, newSize2;\n    NSRect        theFrame, theFrame1, theFrame2;\n    BOOL ')
move = method(document_source, '- (void) doMove: (id)sender')
separate = method(document_source, '- (void) doSeparateWindows: (id)sender')
fragments = [('complete method: placeSplitViewForToolbar', window_source, place)] + [
             ('complete method: ' + m[9:], window_source, method(window_source, m))
             for m in ('- (void) takeSplitViewOutsets', '- (void) fitSplitViewToContent', '- (void) releaseSplitViewPlacement')]

# The call sites, checked in the production source.
split_site = ('         [self.pdfKitSplitView adjustSubviews];\n'
              '        // Side by side, the parts start below the toolbar before they are given their pages.\n'
              '        [self placeSplitViewForToolbar];\n')
unsplit_site = ('        [self.myPDFKitView2 removeFromSuperview];\n'
                '        // The part that stays runs under the toolbar again.\n'
                '        [self placeSplitViewForToolbar];\n')
move_site = ('            [self.pdfKitWindow releaseSplitViewPlacement];\n'
             '            [self.pdfKitWindow.pdfKitSplitView removeFromSuperview];\n')
back_site = ('            // The frame it had in the Preview window, 2 points below the bottom edge included;\n'
             '            // parts side by side start below the toolbar again.\n'
             '            [self.pdfKitWindow fitSplitViewToContent];\n'
             '            [self.pdfKitWindow placeSplitViewForToolbar];\n')

if args.mutation:
    where, old, new = MUTATIONS[args.mutation]
    if where == 'place':
        assert place.count(old) == 1, args.mutation; place = place.replace(old, new)
    elif where == 'release':
        assert release.count(old) == 1, args.mutation; release = release.replace(old, new)
    elif where == 'main':
        assert main.count(old) == 1, args.mutation; main = main.replace(old, new)
    else:
        assert (move + separate).count(old) == 1, args.mutation
        move = move.replace(old, new); separate = separate.replace(old, new)

site_failures = []
def site(text, fragment, label):
    if text.count(fragment) != 1:
        site_failures.append(label)
site(main, split_site, 'splitting places the split view after the second part is added')
site(main, unsplit_site, 'unsplitting places the split view after the second part is removed')
site(move, move_site, 'moving into the combined window hands the split view back before it leaves')
site(separate, back_site, 'moving back gives the split view its frame and places it again')
# Splitting places the split view before the second part gets its pages and magnification.
if not site_failures:
    assert main.index(split_site) < main.index('[self.myPDFKitView2 setDocument:[self.myPDFKitView document]];')

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"

static int failures = 0, checks = 0;
static void Check(BOOL ok, NSString *what) {
    checks++;
    if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); }
}

@interface BandToolbar : NSObject <NSToolbarDelegate>
@end
@implementation BandToolbar
- (NSArray *)items { return @[@"a", @"b", NSToolbarFlexibleSpaceItemIdentifier, @"c"]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = identifier; item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    return item;
}
@end
static BandToolbar *toolbarDelegate;

// The Preview window's state that the production methods use.
@interface PreviewWindow : NSWindow
@property (nonatomic) BOOL windowIsSplit;
@property (weak) NSSplitView *pdfKitSplitView;
@property (strong) NSArray<NSLayoutConstraint *> *splitViewPlacement;
@property NSEdgeInsets splitViewOutsets;
@property BOOL splitViewOutsetsTaken;
- (void) placeSplitViewForToolbar;
- (void) releaseSplitViewPlacement;
- (void) fitSplitViewToContent;
@end
@implementation PreviewWindow
PLACE

RELEASE
@end

static void Settle(NSWindow *window) {
    for (int i = 0; i < 4; i++) {
        [window layoutIfNeeded];
        [window.contentView layoutSubtreeIfNeeded];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.5; }

// A window like the Preview window: a toolbar, the split view 2 points below the bottom edge
// as in the nib, with one part or two.
static PreviewWindow *Window(BOOL fullSize, NSSplitView **outSplit, NSView **outSecond) {
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable;
    if (fullSize) mask |= NSWindowStyleMaskFullSizeContentView;
    PreviewWindow *window = [[PreviewWindow alloc] initWithContentRect:NSMakeRect(100, 100, 900, 640) styleMask:mask
                                                               backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"band"];
    toolbar.delegate = toolbarDelegate; toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.toolbar = toolbar;
    NSView *content = window.contentView;
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, -2, NSWidth(content.bounds), NSHeight(content.bounds) + 2)];
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    split.dividerStyle = NSSplitViewDividerStyleThick;
    [content addSubview:split];
    window.pdfKitSplitView = split;
    NSView *first = [[NSView alloc] initWithFrame:split.bounds];
    [split addSubview:first];
    *outSplit = split;
    *outSecond = [[NSView alloc] initWithFrame:split.bounds];
    Settle(window);
    return window;
}

static void Split(PreviewWindow *window, NSSplitView *split, NSView *second, BOOL vertical) {
    split.vertical = vertical;
    [split addSubview:second];
    [split adjustSubviews];
    window.windowIsSplit = YES;
    [window placeSplitViewForToolbar];
    Settle(window);
}

static void Unsplit(PreviewWindow *window, NSSplitView *split, NSView *second) {
    window.windowIsSplit = NO;
    [second removeFromSuperview];
    [window placeSplitViewForToolbar];
    [split adjustSubviews];
    Settle(window);
}

// The split view in the window as the nib has it: the content view's bounds, and 2 points below.
static BOOL AsInNib(PreviewWindow *window, NSSplitView *split) {
    NSRect bounds = window.contentView.bounds, frame = split.frame;
    return split.translatesAutoresizingMaskIntoConstraints && Near(NSMinX(frame), NSMinX(bounds)) && Near(NSMinY(frame), NSMinY(bounds) - 2) &&
        Near(NSWidth(frame), NSWidth(bounds)) && Near(NSHeight(frame), NSHeight(bounds) + 2);
}

// The top of the area below the toolbar, in the content view.
static CGFloat BandBottom(NSWindow *window) {
    return NSMaxY([window.contentView convertRect:window.contentLayoutRect fromView:nil]);
}

static BOOL BelowBand(PreviewWindow *window, NSSplitView *split, NSString *when) {
    NSView *content = window.contentView;
    NSRect frame = split.frame;
    CGFloat band = NSHeight(content.bounds) - BandBottom(window);
    BOOL top = Near(NSMaxY(frame), BandBottom(window));
    BOOL rest = Near(NSMinX(frame), 0) && Near(NSWidth(frame), NSWidth(content.bounds)) && Near(NSMinY(frame), -2);
    // The divider ends at the band.
    NSRect divider = NSZeroRect;
    if (split.subviews.count == 2) {
        NSRect a = split.subviews[0].frame;
        divider = [content convertRect:NSMakeRect(NSMaxX(a), 0, split.dividerThickness, NSHeight(split.bounds)) fromView:split];
    }
    Check(band > 20, [NSString stringWithFormat:@"%@: the window has a band under the toolbar (%.1f)", when, band]);
    Check(top, [NSString stringWithFormat:@"%@: the split view starts at the bottom of the band (top %.1f, band bottom %.1f)", when, NSMaxY(frame), BandBottom(window)]);
    Check(NSMaxY(divider) <= BandBottom(window) + 0.5, [NSString stringWithFormat:@"%@: the divider ends at the band (%.1f)", when, NSMaxY(divider)]);
    Check(rest, [NSString stringWithFormat:@"%@: the split view keeps its sides and reaches 2 points below the bottom edge (%@)", when, NSStringFromRect(frame)]);
    return top && rest;
}

static void CheckFullSize(void) {
    NSSplitView *split; NSView *second;
    PreviewWindow *window = Window(YES, &split, &second);
    NSView *content = window.contentView;
    Check(BandBottom(window) < NSHeight(content.bounds) - 20, @"the content runs under the toolbar");

    // One part: left as it is.
    [window placeSplitViewForToolbar];
    Settle(window);
    Check(window.splitViewPlacement == nil && AsInNib(window, split), @"one part runs under the toolbar as before");

    // Side by side: below the band.
    Split(window, split, second, YES);
    Check(window.splitViewPlacement != nil, @"parts side by side are placed below the toolbar");
    BelowBand(window, split, @"side by side");

    // A second call keeps the same constraints.
    NSArray *placement = window.splitViewPlacement;
    [window placeSplitViewForToolbar];
    Check(window.splitViewPlacement == placement, @"placing again keeps the constraints");

    // The band gets higher with a title bar accessory, as with the annotation toolbar.
    NSTitlebarAccessoryViewController *accessory = [NSTitlebarAccessoryViewController new];
    accessory.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 30)];
    accessory.layoutAttribute = NSLayoutAttributeBottom;
    CGFloat before = BandBottom(window);
    [window addTitlebarAccessoryViewController:accessory];
    Settle(window);
    Check(BandBottom(window) < before - 10, @"the accessory makes the band higher");
    BelowBand(window, split, @"with an accessory under the toolbar");
    [window removeTitlebarAccessoryViewControllerAtIndex:0];
    Settle(window);
    BelowBand(window, split, @"after the accessory is removed");

    // The toolbar is hidden: the band is the title bar only.
    window.toolbar.visible = NO;
    Settle(window);
    BelowBand(window, split, @"with the toolbar hidden");
    window.toolbar.visible = YES;
    Settle(window);

    // Another size.
    [window setContentSize:NSMakeSize(700, 500)];
    Settle(window);
    BelowBand(window, split, @"after the window got smaller");

    // Unsplit: the split view gets its frame back, under the toolbar.
    Unsplit(window, split, second);
    Check(window.splitViewPlacement == nil, @"unsplitting removes the placement");
    Check(AsInNib(window, split), [NSString stringWithFormat:@"unsplitting gives the split view its frame back (%@ in %@)",
                                   NSStringFromRect(split.frame), NSStringFromRect(content.bounds)]);
    [window setContentSize:NSMakeSize(820, 560)];
    Settle(window);
    Check(AsInNib(window, split), @"the split view given back follows the window's size again");

    // One above the other: under the toolbar as before.
    Split(window, split, second, NO);
    Check(window.splitViewPlacement == nil && AsInNib(window, split), @"parts one above the other run under the toolbar as before");
    Unsplit(window, split, second);

    // Side by side again, then into another window and back, as with the combined window.
    Split(window, split, second, YES);
    BelowBand(window, split, @"side by side again");
    NSWindow *combined = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    combined.releasedWhenClosed = NO;
    [window releaseSplitViewPlacement];
    [split removeFromSuperview];
    [combined.contentView addSubview:split];
    split.frame = combined.contentView.bounds;
    // Constraints against the Preview window's content view would have no common ancestor here.
    BOOL raised = NO;
    @try { [window placeSplitViewForToolbar]; } @catch (NSException *exception) { raised = YES; }
    Check(!raised, @"placing a split view that is in another window raises nothing");
    Settle(combined);
    Check(window.splitViewPlacement == nil && split.translatesAutoresizingMaskIntoConstraints &&
          NSEqualRects(split.frame, combined.contentView.bounds), @"in another window the split view keeps the frame that window gives it");
    [split removeFromSuperview];
    [content addSubview:split];
    BACKSTEP
    [window placeSplitViewForToolbar];
    Settle(window);
    Check(window.splitViewPlacement != nil && Near(NSMaxY(split.frame), BandBottom(window)), @"back in the Preview window the parts start below the toolbar again");
    BelowBand(window, split, @"back from the combined window");
    Unsplit(window, split, second);
    Check(AsInNib(window, split), [NSString stringWithFormat:@"after the combined window, unsplitting gives the split view its frame back, 2 points below (%@)", NSStringFromRect(split.frame)]);
    // Unsplit into the combined window and back: the frame of the nib again.
    [window releaseSplitViewPlacement];
    [split removeFromSuperview];
    [combined.contentView addSubview:split];
    split.frame = combined.contentView.bounds;
    [split removeFromSuperview];
    [content addSubview:split];
    BACKSTEP
    [window placeSplitViewForToolbar];
    Settle(window);
    Check(window.splitViewPlacement == nil && AsInNib(window, split), [NSString stringWithFormat:@"one part back from the combined window has the frame of the nib (%@)", NSStringFromRect(split.frame)]);
    [combined close];
    [window close];
}

static void CheckNotFullSize(void) {
    NSSplitView *split; NSView *second;
    PreviewWindow *window = Window(NO, &split, &second);
    Split(window, split, second, YES);
    Check(window.splitViewPlacement == nil && AsInNib(window, split), @"without content under the toolbar, parts side by side stay as they were");
    Unsplit(window, split, second);
    Check(AsInNib(window, split), @"without content under the toolbar, unsplitting leaves the split view as it was");
    [window close];
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    toolbarDelegate = [BandToolbar new];
    CheckFullSize();
    CheckNotFullSize();
    SITES
    if (failures) { printf("%d of %d checks failed\n", failures, checks); return 1; }
    printf("PASS: Preview parts side by side start below the toolbar and give the split view back (%d checks)\n", checks);
    return 0;
}}
'''
back_start = separate.index('            [[self.pdfKitWindow contentView] addSubview: self.pdfKitWindow.pdfKitSplitView];\n')
back_end = separate.find('            [self.pdfKitWindow placeSplitViewForToolbar];\n', back_start)
back_lines = separate[back_start:back_end if back_end >= 0 else separate.index('            [self.pdfKitWindow orderFront:self];\n', back_start)]
back_step = '\n'.join(l.strip() for l in back_lines.splitlines()[1:] if l.strip() and not l.strip().startswith('//'))
back_step = back_step.replace('self.pdfKitWindow.pdfKitSplitView', 'split').replace('[self.pdfKitWindow contentView]', 'content').replace('self.pdfKitWindow', 'window')
program = program.replace('PLACE', place).replace('RELEASE', release).replace('BACKSTEP', back_step or '/* nothing */')
program = program.replace('SITES', '\n    '.join('Check(NO, @"%s");' % failure for failure in site_failures)
                          + ''.join('\n    Check(YES, @"%s");' % label for label in
                                    ['the production call sites are in place'] if not site_failures))
if not args.mutation:
    verify_embedded(program, fragments)

with tempfile.TemporaryDirectory(prefix='texshop-preview-side-split-band-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *include_args(root), '-I' + str(root / 'Tests'),
                    str(temp / 'test.m'), '-o', str(temp / 'test')], check=True)
    home = temp / 'home'; (home / 'Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(temp / 'test')], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temp) + '/'),
                            capture_output=True, text=True, timeout=120)
    sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
    if args.mutation:
        if result.returncode == 0 or 'FAIL:' not in result.stdout:
            print('FAIL: mutation ' + args.mutation + ' was not detected'); sys.exit(1)
        print('PASS: detected mutation ' + args.mutation); sys.exit(0)
    sys.exit(result.returncode)
