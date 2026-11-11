#!/usr/bin/env python3
"""The divider of the window that shows the source and the Preview side by side.

When the user drags the divider, the share of the window taken by the source is
remembered, once for all documents. A window that opens later puts its divider
there, whichever side the source is on and however wide the window is. Window
resizes and divider moves made by the program are not remembered, and shares
near the edges are kept away from them.

The production TSFullSplitDivider and TSDocument's restoreFullSplitDivider run
unchanged on the windows of the compiled TSDocument nibs of every language,
which are never ordered on screen. The divider is dragged through NSSplitView's
own tracking: a mouse-down on the divider, with the drag and the mouse-up queued
as events for the window.
"""
import argparse, re, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file

MUTATIONS = {
    'not-restored-on-move': ('TSDocument.m',
        '               [fullSplitWindow setFrameFromString:splitPosition];\n            [self restoreFullSplitDivider];\n',
        '               [fullSplitWindow setFrameFromString:splitPosition];\n'),
    'not-restored-with-state': ('TSDocument.m',
        '                [fullSplitWindow setFrameFromString:windowState];\n            }\n            \n'
        '            if ([coder containsValueForKey:@"SplitVisiblePDFPage"])',
        '                [fullSplitWindow setFrameFromString:windowState];\n                [self restoreFullSplitDivider];\n            }\n            \n'
        '            if ([coder containsValueForKey:@"SplitVisiblePDFPage"])'),
    'every-resize': ('TSFullSplitDivider.m',
        '    if (self.restoring || ![TSPreviewSplitDivider isDividerDrag:notification])\n',
        '    if (self.restoring)\n'),
    'left-share': ('TSFullSplitDivider.m',
        '    CGFloat left = source == splitView.subviews.firstObject ? fraction : 1 - fraction;\n',
        '    CGFloat left = fraction;\n'),
    'edges-kept': ('TSFullSplitDivider.m',
        '    CGFloat fraction = MIN(MAX(NSWidth(source.frame) / width, TSFullSplitMinimumFraction), 1 - TSFullSplitMinimumFraction);\n',
        '    CGFloat fraction = NSWidth(source.frame) / width;\n'),
    'garbage-used': ('TSFullSplitDivider.m',
        '    if (!isfinite(fraction) || fraction <= 0 || fraction >= 1)\n        return 0;\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
names = ('TSFullSplitDivider.m', 'TSPreviewSplitDivider.m', 'TSDocument.m')
text = {name: source_file(root, name).read_text(encoding='latin1') for name in names}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert text[name].count(old) == 1, args.mutation
    text[name] = text[name].replace(old, new)

document = text['TSDocument.m']
def method(selector):
    start = document.index('\n' + selector) + 1
    return document[start:document.index('\n}\n', start) + 3]

# Opening the combined window, from the start or from separate windows: the
# window gets its frame, then the divider its place, before it is shown.
move = method('- (void) doMove: (id)sender;')
frame = move.index('[fullSplitWindow setFrameFromString:splitPosition];')
place = move.find('[self restoreFullSplitDivider];')
shown = move.index('[self.splitController showWindow: nil];')
restored_on_move = frame < place < shown
# Restoring a combined window when TeXShop starts: after the window's own frame.
state = method('- (void)restoreStateWithCoder:(NSCoder *)coder')
split_state = state[state.index('if (fromFullSplitWindow) {'):]
restored_with_state = re.search(r'\[fullSplitWindow setFrameFromString:windowState\];\s*\}\s*'
    r'(?:.|\n)*?\[self restoreFullSplitDivider\];', split_state) is not None
# The production method, compiled into a stand-in with the same instance variables.
restore_method = method('- (void) restoreFullSplitDivider')

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSFullSplitDivider.h"
#import "globals.h"
static int failures;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }

// The nib's File's Owner; only the outlets used here are kept.
static NSMutableDictionary *outlets;
@interface TSDocument : NSObject
{
@public
    NSView *leftView, *rightView, *splitView;
}
@property (strong) TSFullSplitDivider *fullSplitDivider;
@end
@implementation TSDocument
- (void)setValue:(id)value forUndefinedKey:(NSString *)key { if (value) outlets[key] = value; }
RESTORE_METHOD
@end
static void Register(NSString *name, Class base) {
    Class c = objc_allocateClassPair(base, name.UTF8String, 0);
    objc_registerClassPair(c);
}

static NSEvent *MouseEvent(NSWindow *window, NSEventType type, NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}
// Drags the divider to a position, through NSSplitView's own tracking.
static void DragDivider(NSSplitView *split, CGFloat position) {
    NSWindow *window = split.window;
    CGFloat half = split.dividerThickness / 2, y = NSMidY(split.bounds);
    NSPoint from = [split convertPoint:NSMakePoint(NSMaxX(split.subviews[0].frame) + half, y) toView:nil];
    NSPoint to = [split convertPoint:NSMakePoint(position + half, y) toView:nil];
    [NSApp postEvent:MouseEvent(window, NSEventTypeLeftMouseDragged, to) atStart:NO];
    [NSApp postEvent:MouseEvent(window, NSEventTypeLeftMouseUp, to) atStart:NO];
    [split mouseDown:MouseEvent(window, NSEventTypeLeftMouseDown, from)];
    [window layoutIfNeeded];
}

static NSData *nibData;
static NSWindow *window;
static NSSplitView *sides;
// A fresh document with the combined window at a width, the source on one side.
static TSDocument *Open(CGFloat width, BOOL sourceOnRight) {
    outlets = [NSMutableDictionary dictionary];
    TSDocument *doc = [TSDocument new];
    NSArray *objects;
    NSNib *nib = [[NSNib alloc] initWithNibData:nibData bundle:nil];
    if (![nib instantiateWithOwner:doc topLevelObjects:&objects]) return nil;
    // The side views and the source's split view arrive in the instance variables.
    window = outlets[@"fullSplitWindow"];
    sides = (NSSplitView *)doc->leftView.superview;
    // As doMove does: the source goes into one side, the Preview into the other.
    NSView *source = sourceOnRight ? doc->rightView : doc->leftView;
    NSView *preview = sourceOnRight ? doc->leftView : doc->rightView;
    [doc->splitView removeFromSuperview];
    [source addSubview:doc->splitView];
    doc->splitView.frame = source.bounds;
    NSView *pdf = [[NSView alloc] initWithFrame:preview.bounds];
    pdf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [preview addSubview:pdf];
    [window setFrame:NSMakeRect(40, 40, width, 700) display:NO];
    [window layoutIfNeeded];
    return doc;
}
static CGFloat Shared(void) { return NSWidth(sides.bounds) - sides.dividerThickness; }
static CGFloat SourceShare(TSDocument *doc) {
    NSView *side = [doc->splitView isDescendantOf:doc->leftView] ? doc->leftView : doc->rightView;
    return NSWidth(side.frame) / Shared();
}
static double Remembered(void) { return [NSUserDefaults.standardUserDefaults doubleForKey:FullSplitSourceFractionKey]; }
static BOOL Near(double a, double b) { return fabs(a - b) < 0.006; }

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    Check(RESTORED_ON_MOVE, @"opening the combined window puts the divider in place after the frame and before showing it");
    Check(RESTORED_WITH_STATE, @"a combined window restored at launch puts the divider in place after its frame");
    for (NSString *name in @[@"TSConsoleWindow", @"TSFullSplitWindow", @"TSFullscreenWindow", @"TSHTMLWindow", @"TSLogWindow",
                             @"TSPreviewWindow", @"TSTextEditorWindow"]) Register(name, NSWindow.class);
    Register(@"MyPDFView", NSView.class);
    Register(@"MyPDFKitView", PDFView.class); Register(@"ScrapPDFKitView", PDFView.class);
    Register(@"TSTextView", NSTextView.class); Register(@"ScrapTextView", NSTextView.class);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    for (int i = 1; i < argc; i++) {
        NSString *nibName = [NSString stringWithFormat:@" (%s)", argv[i]];
        nibData = [NSData dataWithContentsOfFile:@(argv[i])];
        [defaults removeObjectForKey:FullSplitSourceFractionKey];

        // Nothing remembered yet: the divider stays where the nib has it.
        TSDocument *doc = Open(1400, NO);
        Check(doc != nil && [sides isKindOfClass:NSSplitView.class] && sides.isVertical && sides.subviews.count == 2,
              [@"the combined window has two sides" stringByAppendingString:nibName]);
        // The other languages have the same window: one remembered share is used there.
        if (i > 1) {
            [defaults setDouble:0.3 forKey:FullSplitSourceFractionKey];
            [doc restoreFullSplitDivider];
            TSDocument *swapped = Open(1000, YES);
            [swapped restoreFullSplitDivider];
            Check(Near(SourceShare(doc), 0.3) && Near(SourceShare(swapped), 0.3),
                  [@"the window opens with the remembered share" stringByAppendingString:nibName]);
            continue;
        }
        CGFloat before = SourceShare(doc);
        [doc restoreFullSplitDivider];
        Check(Near(SourceShare(doc), before) && Remembered() == 0,
              [@"before any drag the divider stays where it was" stringByAppendingString:nibName]);

        // Dragging the divider remembers the source's share.
        DragDivider(sides, 350);
        Check(Near(SourceShare(doc), 350 / Shared()), [@"the divider was dragged" stringByAppendingString:nibName]);
        double dragged = Remembered();
        Check(Near(dragged, 350 / Shared()), [@"dragging the divider remembers the source's share" stringByAppendingString:nibName]);

        // Window resizes and the program's own moves are not remembered.
        [window setFrame:NSMakeRect(40, 40, 1100, 700) display:NO];
        [window layoutIfNeeded];
        Check(Remembered() == dragged, [@"resizing the window is not remembered" stringByAppendingString:nibName]);
        Check(fabs(SourceShare(doc) - dragged) < 0.02, [@"resizing the window keeps the share" stringByAppendingString:nibName]);
        [sides setPosition:700 ofDividerAtIndex:0];
        Check(Remembered() == dragged, [@"moving the divider from the program is not remembered" stringByAppendingString:nibName]);

        // A new window of another width, for another document, opens with that share.
        TSDocument *other = Open(1000, NO);
        [other restoreFullSplitDivider];
        Check(Near(SourceShare(other), dragged), [@"a new window opens with the remembered share" stringByAppendingString:nibName]);
        // Restoring is not a drag either.
        Check(Remembered() == dragged, [@"opening does not change what is remembered" stringByAppendingString:nibName]);

        // With the source on the right, the source keeps its share.
        TSDocument *swapped = Open(1200, YES);
        [swapped restoreFullSplitDivider];
        Check([swapped->splitView isDescendantOf:swapped->rightView] && Near(SourceShare(swapped), dragged),
              [@"with the source on the right, the source opens with its share" stringByAppendingString:nibName]);
        DragDivider(sides, 0.6 * Shared());
        Check(Near(Remembered(), 0.4), [@"dragging with the source on the right remembers the source's share" stringByAppendingString:nibName]);
        TSDocument *back = Open(1300, NO);
        [back restoreFullSplitDivider];
        Check(Near(SourceShare(back), 0.4), [@"that share is used with the source on the left again" stringByAppendingString:nibName]);

        // A side dragged to nothing, or nearly so, opens at a usable width.
        DragDivider(sides, 0);
        Check(Near(Remembered(), 0.1), [@"a source dragged away is remembered at a tenth" stringByAppendingString:nibName]);
        Check(![sides isSubviewCollapsed:sides.subviews[0]], [@"no side is folded away" stringByAppendingString:nibName]);
        DragDivider(sides, Shared());
        Check(Near(Remembered(), 0.9), [@"a Preview dragged away leaves the source nine tenths" stringByAppendingString:nibName]);
        TSDocument *wide = Open(1000, NO);
        [wide restoreFullSplitDivider];
        Check(Near(SourceShare(wide), 0.9), [@"the Preview opens at a tenth" stringByAppendingString:nibName]);

        // Values that are not a share are left alone.
        for (id value in @[@0, @-0.3, @1, @4.5, @(NAN), @"wide"]) {
            [defaults setObject:value forKey:FullSplitSourceFractionKey];
            TSDocument *odd = Open(1000, NO);
            CGFloat nib = SourceShare(odd);
            [odd restoreFullSplitDivider];
            Check(Near(SourceShare(odd), nib), [[NSString stringWithFormat:@"a stored %@ leaves the divider alone", value]
                                               stringByAppendingString:nibName]);
        }
        Check([TSFullSplitDivider usableFraction:0.02] == 0.1 && [TSFullSplitDivider usableFraction:0.97] == 0.9 &&
              Near([TSFullSplitDivider usableFraction:0.3], 0.3), @"shares near the edges are kept a tenth away");
    }
    if (failures) return 1;
    printf("PASS: the source's share of the combined window is remembered by dragging and used when it opens on %d windows\n", argc - 1);
} return 0; }
'''
program = (program.replace('RESTORE_METHOD', restore_method)
           .replace('RESTORED_ON_MOVE', 'YES' if restored_on_move else 'NO')
           .replace('RESTORED_WITH_STATE', 'YES' if restored_with_state else 'NO'))

# All the behaviour on the Base window, and the remembered share on every other language's.
nibs = sorted((str(p) for p in (root / 'Resources/Interfaces').glob('*.lproj/TSDocument.nib/keyedobjects*.nib')),
              key=lambda p: '/Base.lproj/' not in p)
if len(nibs) < 12:
    sys.exit(f'FAIL: only {len(nibs)} compiled TSDocument nibs')
with tempfile.TemporaryDirectory(prefix='texshop-full-split-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    for name in ('TSFullSplitDivider.m', 'TSPreviewSplitDivider.m'):
        (tmp / name).write_text(text[name], encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(tmp / 'TSFullSplitDivider.m'),
                    str(tmp / 'TSPreviewSplitDivider.m'), str(source_file(root, 'globals.m')), '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe'), *nibs], capture_output=True, text=True, timeout=300)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
