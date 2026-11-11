#!/usr/bin/env python3
"""The source in the Experiment window is colored like the document's source.

The production -[TSDocument (SyntaxHighlighting)] category is compiled unchanged onto a
small TSDocument stand-in, with the production -toggleSyntaxColorEntry:. The Experiment
source is a plain NSTextView in a scroll view, as in TSDocument.nib. Windows are never
ordered on screen; a window subclass only reports itself visible. Preferences stay in memory."""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile
from source_tree import include_args

MUTATIONS = {
    'colorize-all-skips-experiment': ('Sources/Editor/TSDocument-Syntax.m',
        '\t[self colorizeVisibleAreaInTextView:textView2];\n\t[self colorizeExperimentSource];\n', '\t[self colorizeVisibleAreaInTextView:textView2];\n'),
    'no-typing-observer': ('Sources/Editor/TSDocument-Syntax.m',
        '    [center addObserver:self selector:@selector(experimentSourceDidChange:)\n                   name:NSTextDidChangeNotification object:scrapTextView];\n', ''),
    'no-scroll-observer': ('Sources/Editor/TSDocument-Syntax.m',
        '        [center addObserver:self selector:@selector(viewBoundsDidChange:)\n                       name:NSViewBoundsDidChangeNotification object:clipView];\n', ''),
    'no-selection-observer': ('Sources/Editor/TSDocument-Syntax.m',
        '    [center addObserver:self selector:@selector(experimentSelectionDidChange:)\n                   name:NSTextViewDidChangeSelectionNotification object:scrapTextView];\n', ''),
    'recolor-off-keeps-experiment': ('Sources/Editor/TSDocument-Syntax.m',
        '\t\t[[scrapTextView layoutManager] removeTemporaryAttribute:NSForegroundColorAttributeName\n\t\t\tforCharacterRange:NSMakeRange(0, scrapTextView.string.length)];\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
syntax = (root / 'Sources/Editor/TSDocument-Syntax.m').read_text(encoding='latin1')
document = (root / 'Sources/Document/TSDocument.m').read_text(encoding='latin1')
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert syntax.count(old) == 1, args.mutation
    syntax = syntax.replace(old, new)
syntax = re.sub(r'^#import .*$', '', syntax, flags=re.M)
start = document.index('- (IBAction)toggleSyntaxColorEntry:sender {')
toggle = document[start:document.index('\n}\n', start) + 3]

KEYS = ['AlwaysHighlightEnabledKey', 'BlockCursorBKey', 'BlockCursorGKey', 'BlockCursorRKey', 'BlockSideKey',
        'BlockWidthKey', 'ColorImmediatelyKey', 'ExceptionListExcludesParametersKey', 'MakeatletterEnabledKey',
        'RightJustifyIfAnyKey', 'RightJustifyKey', 'SyntaxColorFootnoteKey', 'SyntaxColoringEnabledKey',
        'TurnOffCommandSpellCheckKey', 'TurnOffCommentSpellCheckKey', 'TurnOffParameterSpellCheckKey']
defines = '\n'.join(f'#define {k} @"{k[:-3]}"' for k in KEYS)

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#define SUD TSIsolatedAppKitDefaults
DEFINES
NSArray *commandsToSpellCheck, *userCommandsToSpellCheck, *commandsNotToSpellCheck, *userCommandsNotToSpellCheck;
NSInteger g_texChar = '\\';
static int failures;
static void Check(BOOL ok, const char *name) { if (!ok) { printf("FAIL: %s\n", name); failures++; } }

@interface NSTextView (TSTestSpelling)
- (BOOL)usesTeXAwareSpellChecking;
@end
@implementation NSTextView (TSTestSpelling)
- (BOOL)usesTeXAwareSpellChecking { return NO; }
@end

// Reports itself visible without being ordered on screen.
@interface TestWindow : NSWindow
@property BOOL shown;
@end
@implementation TestWindow
- (BOOL)isVisible { return self.shown; }
@end

@interface TSDocument : NSObject {
    @public
    BOOL tagLine, fileIsTex, isLoading, firstTime;
    NSUInteger colorStart, colorEnd;
    NSTimeInterval colorTime;
    NSTextView *textView1, *textView2, *scrapTextView, *textView;
}
@property (strong) NSDictionary *EntryColorAttribute, *commandColorAttribute, *commentColorAttribute,
    *explColorAttribute1, *explColorAttribute2, *explColorAttribute3, *explColorAttribute4, *explColorAttribute5,
    *explColorAttribute6, *explColorAttribute7, *footnoteColorAttribute, *fullwidthSymbolColorAttribute,
    *indexColorAttribute, *markerColorAttribute, *markerColorCurlyAttribute, *markerColorParenAttribute,
    *markerColorSquareAttribute, *regularColorAttribute;
@property BOOL blockCursor, fileIsXML, syntaxColor, syntaxcolorEntry, useExplColor;
@property (strong) NSTextStorage *textStorage;
@property (strong) NSTextView *textView;
- (BOOL)indexColorState;
- (IBAction)doUpdate:(id)sender;
- (void)setupTags;
- (void)colorizeAll;
- (void)colorizeExperimentSource;
- (void)observeExperimentSource;
- (void)reColor:(NSNotification *)notification;
- (void)cursorMoved:(NSTextView *)aTextView;
- (void)removeCurrentLineColor:(NSTextView *)aTextView;
- (void)syntaxColorXML:(NSUInteger *)location from:(NSUInteger)lineStart to:(NSUInteger)lineEnd using:(NSString *)textString with:(NSLayoutManager *)layoutManager;
- (void)syntaxColorLimitedXML:(NSUInteger *)location and:(NSUInteger)lineEnd using:(NSString *)textString with:(NSLayoutManager *)layoutManager;
- (void)syntaxColorXMLCommentsfrom:(NSUInteger)aLineStart to:(NSUInteger)aLineEnd using:(NSString *)textString with:(NSLayoutManager *)layoutManager;
@end
@implementation TSDocument
@synthesize textView = textView;
- (BOOL)indexColorState { return NO; }
- (IBAction)doUpdate:(id)sender {}
- (void)setupTags {}
- (void)syntaxColorXML:(NSUInteger *)location from:(NSUInteger)lineStart to:(NSUInteger)lineEnd using:(NSString *)textString with:(NSLayoutManager *)layoutManager { (*location)++; }
- (void)syntaxColorLimitedXML:(NSUInteger *)location and:(NSUInteger)lineEnd using:(NSString *)textString with:(NSLayoutManager *)layoutManager { (*location)++; }
- (void)syntaxColorXMLCommentsfrom:(NSUInteger)aLineStart to:(NSUInteger)aLineEnd using:(NSString *)textString with:(NSLayoutManager *)layoutManager {}
TOGGLE
@end

SYNTAX

static NSTextView *MakeTextView(TestWindow *window) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    view.verticallyResizable = YES; view.autoresizingMask = NSViewWidthSizable;
    view.textContainer.widthTracksTextView = YES;
    view.font = [NSFont userFixedPitchFontOfSize:12];
    scroll.documentView = view; scroll.hasVerticalScroller = YES;
    window.contentView = scroll;
    return view;
}
static NSColor *Foreground(NSTextView *view, NSUInteger index) {
    return [view.layoutManager temporaryAttributesAtCharacterIndex:index effectiveRange:NULL][NSForegroundColorAttributeName];
}
static NSColor *Background(NSTextView *view, NSUInteger index) {
    return [view.layoutManager temporaryAttributesAtCharacterIndex:index effectiveRange:NULL][NSBackgroundColorAttributeName];
}
static NSUInteger Find(NSTextView *view, NSString *text) { return [view.string rangeOfString:text].location; }

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    NSColor *commandColor = NSColor.blueColor, *commentColor = NSColor.redColor, *entryColor = NSColor.yellowColor;
    TSDocument *doc = [TSDocument new];
    NSDictionary *plain = @{NSForegroundColorAttributeName: NSColor.textColor};
    for (NSString *key in @[@"explColorAttribute1", @"explColorAttribute2", @"explColorAttribute3", @"explColorAttribute4",
                            @"explColorAttribute5", @"explColorAttribute6", @"explColorAttribute7", @"footnoteColorAttribute",
                            @"indexColorAttribute", @"markerColorAttribute", @"markerColorCurlyAttribute",
                            @"markerColorParenAttribute", @"markerColorSquareAttribute", @"regularColorAttribute"])
        [doc setValue:plain forKey:key];
    doc.commandColorAttribute = @{NSForegroundColorAttributeName: commandColor};
    doc.commentColorAttribute = @{NSForegroundColorAttributeName: commentColor};
    doc.EntryColorAttribute = @{NSBackgroundColorAttributeName: entryColor};
    doc.syntaxColor = YES; doc->fileIsTex = YES;

    TestWindow *mainWindow = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    TestWindow *experiment = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    mainWindow.releasedWhenClosed = NO; experiment.releasedWhenClosed = NO;
    doc->textView1 = MakeTextView(mainWindow); doc->textView2 = nil;
    doc.textView = doc->textView1; doc.textStorage = doc->textView1.textStorage;
    doc->textView1.string = @"\\documentclass{article}";
    NSTextView *scrap = MakeTextView(experiment);
    doc->scrapTextView = scrap;

    // Before the Experiment window is shown, nothing is colored.
    NSMutableString *source = [NSMutableString stringWithString:@"\\section{Top} % first comment\nplain text\n"];
    for (int i = 0; i < 80; i++) [source appendFormat:@"line %d\n", i];
    [source appendString:@"\\bottom % last comment\n"];
    scrap.string = source;
    [doc observeExperimentSource];
    [doc colorizeExperimentSource];
    Check(Foreground(scrap, 0) == nil, "a hidden Experiment window is not colored");

    // Shown (tryScrap: observes and colors it): the visible lines get the source colors.
    experiment.shown = YES;
    [doc observeExperimentSource];
    [doc colorizeExperimentSource];
    Check([Foreground(scrap, 0) isEqual:commandColor], "a command in the Experiment source has the command color");
    Check([Foreground(scrap, Find(scrap, @"% first")) isEqual:commentColor], "a comment in the Experiment source has the comment color");
    Check(![Foreground(scrap, Find(scrap, @"plain")) isEqual:commentColor], "text after a comment line keeps the text color");
    Check(Foreground(scrap, Find(scrap, @"\\bottom")) == nil, "lines out of view wait until they are scrolled into view");

    // Scrolling colors the lines that come into view.
    // Layout is completed first, so that only the clip view's bounds change.
    NSClipView *clip = scrap.enclosingScrollView.contentView;
    [scrap.layoutManager ensureLayoutForTextContainer:scrap.textContainer];
    [scrap sizeToFit];
    NSRect bottomLine = [scrap.layoutManager boundingRectForGlyphRange:
        [scrap.layoutManager glyphRangeForCharacterRange:NSMakeRange(Find(scrap, @"\\bottom"), 1) actualCharacterRange:NULL]
        inTextContainer:scrap.textContainer];
    NSRect frameBefore = scrap.frame;
    [clip scrollToPoint:NSMakePoint(0, NSMaxY(bottomLine) - NSHeight(clip.bounds) + 4)];
    Check(NSEqualRects(frameBefore, scrap.frame) && NSMinY(clip.bounds) > 0, "only the clip view scrolled");
    Check([Foreground(scrap, Find(scrap, @"\\bottom")) isEqual:commandColor], "scrolling colors the lines that come into view");

    // Typing colors the edited line; a line break moves text out of the comment color.
    [scrap scrollRangeToVisible:NSMakeRange(0, 0)];
    [scrap setSelectedRange:NSMakeRange(Find(scrap, @"plain text") + 10, 0)];
    [scrap insertText:@" % typed" replacementRange:scrap.selectedRange];
    Check([Foreground(scrap, Find(scrap, @"% typed")) isEqual:commentColor], "typing colors the edited line");
    [scrap setSelectedRange:NSMakeRange(Find(scrap, @"% first"), 0)];
    [scrap insertText:@"\n" replacementRange:scrap.selectedRange];
    Check(![Foreground(scrap, Find(scrap, @"\\section")) isEqual:commentColor] && [Foreground(scrap, Find(scrap, @"% first")) isEqual:commentColor],
          "a comment moved to a new line by typing keeps its color and the line before loses none");

    // Recoloring the document (theme change, Syntax Color on) includes the Experiment source.
    [scrap.layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(0, scrap.string.length)];
    [doc colorizeAll];
    Check([Foreground(scrap, 0) isEqual:commandColor], "recoloring the document recolors the Experiment source");

    // Syntax Color off removes the colors.
    doc.syntaxColor = NO;
    [doc reColor:nil];
    Check(Foreground(scrap, 0) == nil && Foreground(scrap, Find(scrap, @"% first")) == nil, "Syntax Color off removes the Experiment colors");
    [scrap insertText:@"x" replacementRange:NSMakeRange(0, 0)];
    Check(Foreground(scrap, 1) == nil, "with Syntax Color off, typing adds no color");
    doc.syntaxColor = YES;
    [doc reColor:nil];
    Check([Foreground(scrap, 1) isEqual:commandColor], "Syntax Color on colors the Experiment source again");

    if (getenv("TS_EXPERIMENT_COLOR_PNG")) {
        [scrap scrollRangeToVisible:NSMakeRange(0, 0)];
        NSView *shown = scrap.enclosingScrollView;
        NSBitmapImageRep *rep = [shown bitmapImageRepForCachingDisplayInRect:shown.bounds];
        [shown cacheDisplayInRect:shown.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(getenv("TS_EXPERIMENT_COLOR_PNG")) atomically:YES];
    }

    // The active line follows the insertion point, and the toggle applies to the Experiment source.
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    [doc toggleSyntaxColorEntry:item];
    Check(doc.syntaxcolorEntry, "active line coloring is on");
    [scrap setSelectedRange:NSMakeRange(Find(scrap, @"plain"), 0)];
    Check([Background(scrap, Find(scrap, @"plain")) isEqual:entryColor], "the active line in the Experiment source is highlighted");
    [scrap setSelectedRange:NSMakeRange(Find(scrap, @"line 0"), 0)];
    Check([Background(scrap, Find(scrap, @"line 0")) isEqual:entryColor] && Background(scrap, Find(scrap, @"plain")) == nil,
          "moving the insertion point moves the highlight");
    [doc toggleSyntaxColorEntry:item];
    Check(!doc.syntaxcolorEntry && Background(scrap, Find(scrap, @"line 0")) == nil, "turning active line coloring off removes the highlight");

    // The document's own source is still colored by the same code.
    [doc colorizeAll];
    Check([Foreground(doc->textView1, 0) isEqual:commandColor], "the document source is colored as before");

    if (failures) return 1;
    printf("PASS: Experiment source colored on showing, typing, scrolling, recoloring and Syntax Color, with the active line\n");
} return 0; }
'''.replace('DEFINES', defines).replace('TOGGLE', toggle).replace('SYNTAX', syntax)

with tempfile.TemporaryDirectory(prefix='texshop-experiment-color-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=120)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
