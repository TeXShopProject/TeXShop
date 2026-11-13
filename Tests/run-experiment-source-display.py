#!/usr/bin/env python3
"""The source in the Experiment window shows its text as the document's source does.

Syntax colors, the active line, the block cursor, the index color, the font, tabs and
line spacing, wrapping, invisible characters, line numbers and brace matching follow the
document, at once, when they change from a menu or from Settings.

The production categories TSDocument (SyntaxHighlighting) and TSDocument (ExperimentSource)
are compiled unchanged onto a small TSDocument stand-in, with the production TSDocument
methods that change these settings and match braces, the overrides of ScrapTextView, and
the real TSLayoutManager and NoodleLineNumberView. Windows are never ordered on screen;
a window subclass only reports itself visible. Preferences stay in memory."""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile
from source_tree import include_args, source_file

SYNTAX = 'Sources/Editor/TSDocument-Syntax.m'
EXPERIMENT = 'Sources/Editor/TSDocument-ExperimentSource.m'
DOCUMENT = 'Sources/Document/TSDocument.m'
SCRAP_VIEW = 'Sources/Editor/ScrapTextView.m'
SCRAP = 'Sources/Document/TSDocument-Scrap.m'
XML = 'Sources/Document/TSDocument-XML.m'
TEXT_VIEW = 'Sources/Editor/TSTextView.m'

MUTATIONS = {
    'colorize-all-skips-experiment': (SYNTAX,
        '\t[self colorizeVisibleAreaInTextView:textView2];\n\t[self colorizeExperimentSource];\n', '\t[self colorizeVisibleAreaInTextView:textView2];\n'),
    'no-typing-observer': (EXPERIMENT,
        '    [center addObserver:self selector:@selector(experimentSourceDidChange:)\n                   name:NSTextDidChangeNotification object:scrapTextView];\n', ''),
    'no-scroll-observer': (EXPERIMENT,
        '        [center addObserver:self selector:@selector(viewBoundsDidChange:)\n                       name:NSViewBoundsDidChangeNotification object:clipView];\n', ''),
    'no-selection-observer': (EXPERIMENT,
        '    [center addObserver:self selector:@selector(experimentSelectionDidChange:)\n                   name:NSTextViewDidChangeSelectionNotification object:scrapTextView];\n', ''),
    'recolor-off-keeps-experiment': (SYNTAX,
        '\t\t[[scrapTextView layoutManager] removeTemporaryAttribute:NSForegroundColorAttributeName\n\t\t\tforCharacterRange:NSMakeRange(0, scrapTextView.string.length)];\n', ''),
    'no-insertion-point-override': (SCRAP_VIEW,
        '        [self.document performSelector:@selector(cursorMoved:) withObject:self afterDelay:0];\n', '        ;\n'),
    'no-font-hook': (DOCUMENT,
        '\t[textView2 setDefaultParagraphStyle: newStyle];\n\t[self applyExperimentTextLayout];\n', '\t[textView2 setDefaultParagraphStyle: newStyle];\n'),
    'interline-unranged': (DOCUMENT,
        '    CGFloat                     interlinespace      = TSStoredIntegerInRange(SUD, SourceInterlineSpaceKey, TSInterlineSpaceRange);\n',
        '    CGFloat                     interlinespace      = [SUD floatForKey: SourceInterlineSpaceKey];\n'),
    'indent-unranged': (DOCUMENT,
        '    CGFloat                     myHeadIndent          = TSStoredIntegerInRange(SUD, SourceHeadIndentKey, TSParagraphIndentRange);\n',
        '    CGFloat                     myHeadIndent          = [SUD floatForKey: SourceHeadIndentKey];\n'),
    'tabs-unranged': (DOCUMENT,
        '\tNSUInteger\t\t\t\t\ttabWidth\t\t\t= TSStoredIntegerInRange(SUD, tabsKey, TSTabWidthRange);\n',
        '\tNSUInteger\t\t\t\t\ttabWidth\t\t\t= [SUD integerForKey: tabsKey];\n'),
    'no-line-break-hook': (DOCUMENT,
        '\t[textView2 setDefaultParagraphStyle: styleNew];\n\t[self applyExperimentTextLayout];\n', '\t[textView2 setDefaultParagraphStyle: styleNew];\n'),
    'wrap-keeps-wide-container': (EXPERIMENT,
        '        container.containerSize = NSMakeSize(MAX(contentSize.width - 2 * scrapTextView.textContainerInset.width, 0), FLT_MAX);\n', ''),
    'no-invisible-hook': (DOCUMENT,
        '\t[self applyExperimentInvisibleCharacters];\n', ''),
    'no-line-number-hook': (DOCUMENT,
        '\t[self applyExperimentLineNumbers];\n', ''),
    'no-index-color-hook': (DOCUMENT,
        '    [self colorizeVisibleAreaInTextView:textView2];\n    [self colorizeExperimentSource];\n', '    [self colorizeVisibleAreaInTextView:textView2];\n'),
    'no-block-cursor-hook': (DOCUMENT,
        '    [self cursorMoved: textView];\n    [self refreshExperimentCurrentLine];\n }', '    [self cursorMoved: textView];\n }'),
    'sync-skips-line-numbers': (EXPERIMENT,
        '    [self applyExperimentInvisibleCharacters];\n    [self applyExperimentLineNumbers];\n', '    [self applyExperimentInvisibleCharacters];\n'),
    'try-scrap-skips-sync': (SCRAP,
        '    [self syncExperimentSourceDisplay];\n', ''),
    'braces-use-document-state': (DOCUMENT,
        '\tBOOL experiment = (aTextView != nil && aTextView == scrapTextView);\n', '\tBOOL experiment = NO;\n'),
    'flash-in-document-view': (DOCUMENT,
        '\tNSTextView *flashView = experiment ? scrapTextView : textView;\n', '\tNSTextView *flashView = textView;\n'),
    'no-xml-hook': (XML,
        '    [self colorizeVisibleAreaInTextView:textView2];\n    [self colorizeExperimentSource];\n', '    [self colorizeVisibleAreaInTextView:textView2];\n'),
    'experiment-font-stays-local': (SCRAP_VIEW,
        '    [self.document applyExperimentFontToSource:self.font];\n', ''),
    'no-typed-match-override': (SCRAP_VIEW,
        '        [self.document flashMatchForCharacter:replacementString range:affectedCharRange inTextView:self];\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = {path: (root / path).read_text(encoding='latin1') for path in (SYNTAX, EXPERIMENT, DOCUMENT, SCRAP_VIEW, SCRAP, XML, TEXT_VIEW)}
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert text[path].count(old) == 1, args.mutation
    text[path] = text[path].replace(old, new)


def method(source, signature):
    """A method or function from its signature to the closing brace at the start of a line."""
    start = source.index('\n' + signature) + 1
    end = re.compile(r'\n ?\}\n').search(source, start)
    return source[start:end.end()]


def strip_imports(source):
    return re.sub(r'^#import .*$', '', source, flags=re.M)


document = text[DOCUMENT]
DOCUMENT_METHODS = [
    '- (IBAction)toggleSyntaxColorEntry:sender {', '- (IBAction)toggleBlockCursor:sender {',
    '- (void) applyInvisibleCharactersShowing', '- (void) showHideInvisibleCharacters: sender',
    '- (void) showHideLineNumbers: sender', '- (void)setDocumentFontFromPreferences:(NSNotification *)notification',
    '- (void)fixUpTabs {', '- (void)setLineBreakMode:(id)sender', '- (void) flipIndexColor: (NSInteger)state',
    '- (void) showIndexColor: sender', '- (BOOL)indexColorState',
    '- (void)resetHighlight:(id)sender', '- (void)showIndicator:(NSString*)range', '- (void)resetBackgroundColor:(id)sender',
    '- (void)resetBackgroundColorOfTextView:(id)sender', '- (void)highlightContent:(NSString*)range',
    '- (void)highlightBracesAt:(NSArray*)locations',
    '- (void)textViewDidChangeSelection:(NSNotification *)inNotification',
    '- (void)matchBracesForSelectionInTextView:(NSTextView *)aTextView',
    '- (void)flashMatchForCharacter:(NSString *)replacementString range:(NSRange)affectedCharRange inTextView:(NSTextView *)aTextView',
]
document_methods = '\n'.join(method(document, s) for s in DOCUMENT_METHODS)
start = document.index('static const NSInteger kTSBraceSearchLimit')
brace_search = document[start:document.index('\n}\n', document.index('static NSInteger TSFindMatchingBrace(')) + 3]
tab_stops = method(document, 'static NSArray *tabStopArrayForFontAndTabWidth(')
scrap_overrides = '\n'.join(method(text[SCRAP_VIEW], s) for s in [
    '- (void)updateInsertionPointStateAndRestartTimer:(BOOL)restartFlag',
    '- (BOOL)shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString',
    '- (void)changeFont:(id)sender'])
toggle_xml = method(text[XML], ' - (IBAction) toggleXML: sender')
text_view_tabs = method(text[TEXT_VIEW], '- (void)fixupTabs')
try_scrap = method(text[SCRAP], '- (void) tryScrap:(id)sender')

globals_m = source_file(root, 'globals.m').read_text(encoding='latin1')
keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
defines = '\n'.join(f'#define {k} {v}' for k, v in sorted(keys.items()))
marker_keys = '\n'.join(f'NSString *{k} = {keys[k]};' for k in [
    'showSpaceCharacterKey', 'showFullwidthSpaceCharacterKey', 'showTabCharacterKey', 'showNewLineCharacterKey',
    'SpaceCharacterKindKey', 'FullwidthSpaceCharacterKindKey', 'TabCharacterKindKey', 'NewLineCharacterKindKey', 'LineNumberSizeKey'])

program = r'''
#import <Cocoa/Cocoa.h>
#import "TSSyntaxTeXScanner.h"
#import "TSSyntaxHighlighter.h"
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSSourceFormatRanges.h"
#import "TSLayoutManager.h"
#define SUD TSIsolatedAppKitDefaults
@@DEFINES@@
#define LEOPARD 568
#define MOJAVEORHIGHER
BOOL atLeastMojave = YES;
NSArray *commandsToSpellCheck, *userCommandsToSpellCheck, *commandsNotToSpellCheck, *userCommandsNotToSpellCheck;
NSDictionary *liteColors, *darkColors, *highlightBracesColorDict, *highlightContentColorDict;
NSInteger g_texChar = '\\';
static int failures;
static void Check(BOOL ok, const char *name) { if (!ok) { printf("FAIL: %s\n", name); failures++; } }
static void Spin(NSTimeInterval seconds) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
// Runs the run loop until the condition holds or the time limit passes; a slow machine waits longer, not in vain.
static void SpinUntil(NSTimeInterval limit, BOOL (^condition)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:limit];
    while (!condition() && [end timeIntervalSinceNow] > 0)
        Spin(0.01);
}

@interface TSTextView : NSTextView
- (void)fixupTabs;
@end
#define CommandCompletionPathXML @"XML"
#define CommandCompletionPathRegular @"Regular"
@interface GlobalData : NSObject
@property (strong) NSString *CommandCompletionPath;
+ (instancetype)sharedGlobalData;
@end
@implementation GlobalData
+ (instancetype)sharedGlobalData { static GlobalData *shared; if (!shared) shared = [GlobalData new]; return shared; }
@end
@interface TSAppDelegate : NSObject
- (void)reReadCommandCompletionData;
@end
@implementation TSAppDelegate
- (void)reReadCommandCompletionData {}
@end
// The font that the Font panel gives; the panel itself is never shown.
static NSFont *PanelFont;
static NSFont *PanelConvertFont(id manager, SEL selector, NSFont *font) { return PanelFont; }

@interface NSText (Extras)
- (void)setFontSafely:(NSFont *)aFont;
@end
@interface NoodleLineNumberView : NSRulerView
- (id)initWithScrollView:(NSScrollView *)aScrollView;
@end
@interface NSTextView (TSTestSpelling)
- (BOOL)usesTeXAwareSpellChecking;
@end
@implementation NSTextView (TSTestSpelling)
- (BOOL)usesTeXAwareSpellChecking { return NO; }
@end

static NSColor *FlashColor, *ThemeBackground;
@interface TSColorSupport : NSObject
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { return [self new]; }
- (NSColor *)colorFromDictionary:(NSDictionary *)dictionary andKey:(NSString *)key { return FlashColor; }
- (NSColor *)darkColorWithKey:(NSString *)key { return FlashColor; }
- (NSColor *)liteColorWithKey:(NSString *)key { return FlashColor; }
@end

// Reports itself visible without being ordered on screen.
@interface TestWindow : NSWindow
@property BOOL shown;
@end
@implementation TestWindow
- (BOOL)isVisible { return self.shown; }
@end

static NSMutableArray<NSString *> *indicators, *flashSelections;
// The document's source; find indicators are recorded, not shown.
@interface TestSourceView : NSTextView
@end
@implementation TestSourceView
@@TEXT_VIEW_TABS@@
- (void)showFindIndicatorForRange:(NSRange)range { [indicators addObject:[@"source " stringByAppendingString:NSStringFromRange(range)]]; }
@end

@interface TSDocument : NSObject {
    @public
    BOOL tagLine, fileIsTex, isLoading, firstTime, lineNumbersShowing, invisibleCharactersShowing, showIndexColor,
         autoCompleting, windowIsSplit, braceHighlighting, contentHighlighting, lastInputIsDelete,
         scrapLastInputIsDelete, scrapBraceHighlighting, scrapContentHighlighting;
    NSInteger lastCursorLocation, lastStringLength, scrapLastCursorLocation, scrapLastStringLength;
    NSUInteger colorStart, colorEnd;
    NSTimeInterval colorTime;
    NSLineBreakMode lineBreakMode;
    NSTextView *textView1, *textView2, *scrapTextView, *textView;
    NSScrollView *scrollView, *scrollView2;
    NSButton *indexColorSplitBox;
}
@property (strong) NSDictionary *EntryColorAttribute, *commandColorAttribute, *commentColorAttribute,
    *explColorAttribute1, *explColorAttribute2, *explColorAttribute3, *explColorAttribute4, *explColorAttribute5,
    *explColorAttribute6, *explColorAttribute7, *footnoteColorAttribute, *fullwidthSymbolColorAttribute,
    *indexColorAttribute, *markerColorAttribute, *markerColorCurlyAttribute, *markerColorParenAttribute,
    *markerColorSquareAttribute, *regularColorAttribute;
@property BOOL blockCursor, fileIsXML, syntaxColor, syntaxcolorEntry, useExplColor, coloringWaitsForMarkedText;
@property (readonly) TSSyntaxColorScheme *syntaxColorScheme;
@property (strong) NSTextStorage *textStorage;
@property (strong) NSTextView *textView;
@property (strong) NSScrollView *logScrollView;
@property (strong) NoodleLineNumberView *lineNumberView1, *lineNumberView2, *logLineNumberView;
@property (strong) NSButton *indexColorBox;
- (BOOL)indexColorState;
- (IBAction)doUpdate:(id)sender;
- (void)setupTags;
- (void)colorizeAll;
- (void)colorizeVisibleAreaInTextView:(NSTextView *)aTextView;
- (BOOL)coloringWaitsForMarkedTextIn:(NSTextView *)aTextView;
- (void)colorAfterMarkedTextEnds;
- (void)reColor:(NSNotification *)notification;
- (void)cursorMoved:(NSTextView *)aTextView;
- (void)removeCurrentLineColor:(NSTextView *)aTextView;
- (void)viewFrameDidChange:(NSNotification *)notification;
- (void)viewBoundsDidChange:(NSNotification *)notification;
- (void)observeExperimentSource;
- (void)syncExperimentSourceDisplay;
- (void)applyExperimentTextLayout;
- (void)applyExperimentInvisibleCharacters;
- (void)applyExperimentLineNumbers;
- (void)colorizeExperimentSource;
- (void)refreshExperimentCurrentLine;
- (void)matchBracesForSelectionInTextView:(NSTextView *)aTextView;
- (void)flashMatchForCharacter:(NSString *)replacementString range:(NSRange)affectedCharRange inTextView:(NSTextView *)aTextView;
- (void)textViewDidChangeSelection:(NSNotification *)inNotification;
- (void)setDocumentFontFromPreferences:(NSNotification *)notification;
- (void)fixUpTabs;
- (void)setLineBreakMode:(id)sender;
- (void)applyInvisibleCharactersShowing;
- (void)showHideInvisibleCharacters:(id)sender;
- (void)showHideLineNumbers:(id)sender;
- (void)flipIndexColor:(NSInteger)state;
- (void)showIndexColor:(id)sender;
- (IBAction)toggleSyntaxColorEntry:(id)sender;
- (IBAction)toggleBlockCursor:(id)sender;
- (IBAction)toggleXML:(id)sender;
- (void)applyExperimentFontToSource:(NSFont *)font;
@end

// The Experiment source, with the production overrides of ScrapTextView.
@interface ScrapTextView : NSTextView
@property (weak) TSDocument *document;
@end
@implementation ScrapTextView
@@SCRAP_OVERRIDES@@
- (void)updateExperimentColors:(NSNotification *)notification { self.backgroundColor = ThemeBackground; }
- (void)showFindIndicatorForRange:(NSRange)range { [indicators addObject:[@"experiment " stringByAppendingString:NSStringFromRange(range)]]; }
- (void)setSelectedRange:(NSRange)range affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelecting
{
    if (stillSelecting) [flashSelections addObject:NSStringFromRange(range)];
    [super setSelectedRange:range affinity:affinity stillSelecting:stillSelecting];
}
@end

@@TAB_STOPS@@
@@BRACE_SEARCH@@

// The document's colors by role, as -changeColorsUsingDictionary: makes them, from the
// attributes the test gives the document; XML is shown in XMLColor.
static NSColor *XMLColor;
static TSSyntaxColorScheme *SchemeOf(TSDocument *doc)
{
    NSDictionary *names = @{
        @(TSSyntaxRoleCommand): @"commandColorAttribute", @(TSSyntaxRoleComment): @"commentColorAttribute",
        @(TSSyntaxRoleMarker): @"markerColorAttribute", @(TSSyntaxRoleBracketParen): @"markerColorParenAttribute",
        @(TSSyntaxRoleBracketCurly): @"markerColorCurlyAttribute", @(TSSyntaxRoleBracketSquare): @"markerColorSquareAttribute",
        @(TSSyntaxRoleIndex): @"indexColorAttribute", @(TSSyntaxRoleFootnote): @"footnoteColorAttribute",
        @(TSSyntaxRoleFullwidthSymbol): @"fullwidthSymbolColorAttribute",
        @(TSSyntaxRoleExplVariable): @"explColorAttribute1", @(TSSyntaxRoleExplFunction): @"explColorAttribute2",
        @(TSSyntaxRoleExplIntenseVariable): @"explColorAttribute3", @(TSSyntaxRoleExplIntenseFunction): @"explColorAttribute4",
        @(TSSyntaxRoleExplMessage): @"explColorAttribute5", @(TSSyntaxRoleExplKey): @"explColorAttribute6",
        @(TSSyntaxRoleExplKeyArgument): @"explColorAttribute7"};
    NSMutableDictionary *roles = [NSMutableDictionary dictionary];
    for (NSNumber *role in names) {
        NSDictionary *attributes = [doc valueForKey:names[role]];
        if (attributes) roles[role] = attributes;
    }
    for (NSNumber *role in @[@(TSSyntaxRoleXMLComment), @(TSSyntaxRoleXMLTag), @(TSSyntaxRoleXMLSpecial), @(TSSyntaxRoleXMLParameter), @(TSSyntaxRoleXMLValue)])
        roles[role] = @{NSForegroundColorAttributeName: XMLColor};
    return [[TSSyntaxColorScheme alloc] initWithAttributes:roles activeLineAttributes:doc.EntryColorAttribute ?: @{}
                                  braceHighlightAttributes:@{} contentHighlightAttributes:@{}];
}
@implementation TSDocument
@synthesize textView = textView;
- (TSSyntaxColorScheme *)syntaxColorScheme { return SchemeOf(self); }
- (IBAction)doUpdate:(id)sender {}
- (void)setupTags {}
@@DOCUMENT_METHODS@@
@@TOGGLE_XML@@
@end

@@SYNTAX@@
@@EXPERIMENT@@

// Invisible characters that TSLayoutManager draws.
static NSMutableArray<NSString *> *drawnMarkers;
static void (*originalDrawMarker)(id, SEL, NSString *, NSUInteger, NSPoint, NSDictionary *, NSMutableDictionary *);
static void RecordMarker(TSLayoutManager *layout, SEL cmd, NSString *marker, NSUInteger glyph, NSPoint origin, NSDictionary *attributes, NSMutableDictionary *cache)
{
    [drawnMarkers addObject:marker];
    originalDrawMarker(layout, cmd, marker, glyph, origin, attributes, cache);
}
static NSBitmapImageRep *Render(NSView *view)
{
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}
static NSUInteger MarkersDrawn(NSTextView *view)
{
    [drawnMarkers removeAllObjects];
    Render(view.enclosingScrollView);
    return drawnMarkers.count;
}

static NSScrollView *MakeScrollView(NSWindow *window) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    scroll.hasVerticalScroller = YES;
    window.contentView = scroll;
    return scroll;
}
static void InstallTextView(NSTextView *view, NSScrollView *scroll) {
    view.verticallyResizable = YES; view.autoresizingMask = NSViewWidthSizable;
    view.textContainer.widthTracksTextView = YES;
    view.font = [NSFont userFixedPitchFontOfSize:12];
    scroll.documentView = view;
}
static NSColor *Foreground(NSTextView *view, NSUInteger index) {
    return [view.layoutManager temporaryAttributesAtCharacterIndex:index effectiveRange:NULL][NSForegroundColorAttributeName];
}
static NSColor *Background(NSTextView *view, NSUInteger index) {
    return [view.layoutManager temporaryAttributesAtCharacterIndex:index effectiveRange:NULL][NSBackgroundColorAttributeName];
}
static NSUInteger Find(NSTextView *view, NSString *text) { return [view.string rangeOfString:text].location; }
// Whether the characters of range are laid out on one line.
static BOOL OnOneLine(NSTextView *view, NSRange range) {
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForTextContainer:view.textContainer];
    NSRect first = [layout lineFragmentRectForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:range.location] effectiveRange:NULL];
    NSRect last = [layout lineFragmentRectForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:NSMaxRange(range) - 1] effectiveRange:NULL];
    return NSMinY(first) == NSMinY(last);
}
static NSMenuItem *Item(NSInteger tag) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    item.tag = tag;
    return item;
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    Check(@@TRY_SCRAP_SYNCS@@, "opening the Experiment window applies the source display settings");
    indicators = [NSMutableArray array]; flashSelections = [NSMutableArray array]; drawnMarkers = [NSMutableArray array];
    Method draw = class_getInstanceMethod(TSLayoutManager.class, @selector(drawInvisibleCharacter:atGlyphIndex:containerOrigin:attributes:cache:));
    originalDrawMarker = (void *)method_getImplementation(draw);
    method_setImplementation(draw, (IMP)RecordMarker);
    FlashColor = NSColor.orangeColor; ThemeBackground = NSColor.whiteColor; XMLColor = NSColor.brownColor;
    NSColor *commandColor = NSColor.blueColor, *commentColor = NSColor.redColor, *entryColor = NSColor.yellowColor;
    NSColor *indexColor = NSColor.greenColor, *braceColor = NSColor.magentaColor, *contentColor = NSColor.cyanColor;
    highlightBracesColorDict = @{NSForegroundColorAttributeName: braceColor};
    highlightContentColorDict = @{NSBackgroundColorAttributeName: contentColor};
    TSDocument *doc = [TSDocument new];
    NSDictionary *plain = @{NSForegroundColorAttributeName: NSColor.textColor};
    for (NSString *key in @[@"explColorAttribute1", @"explColorAttribute2", @"explColorAttribute3", @"explColorAttribute4",
                            @"explColorAttribute5", @"explColorAttribute6", @"explColorAttribute7", @"footnoteColorAttribute",
                            @"markerColorAttribute", @"markerColorCurlyAttribute",
                            @"markerColorParenAttribute", @"markerColorSquareAttribute", @"regularColorAttribute"])
        [doc setValue:plain forKey:key];
    doc.indexColorAttribute = @{NSForegroundColorAttributeName: indexColor};
    doc.commandColorAttribute = @{NSForegroundColorAttributeName: commandColor};
    doc.commentColorAttribute = @{NSForegroundColorAttributeName: commentColor};
    doc.EntryColorAttribute = @{NSBackgroundColorAttributeName: entryColor};
    doc.syntaxColor = YES; doc->fileIsTex = YES; doc->lineBreakMode = NSLineBreakByWordWrapping;

    TestWindow *mainWindow = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    TestWindow *experiment = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    mainWindow.releasedWhenClosed = NO; experiment.releasedWhenClosed = NO;
    doc->scrollView = MakeScrollView(mainWindow);
    doc->scrollView2 = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    doc.logScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    doc->textView1 = [[TestSourceView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    InstallTextView(doc->textView1, doc->scrollView);
    [doc->textView1.textContainer replaceLayoutManager:[TSLayoutManager new]];
    doc->textView2 = nil;
    doc.textView = doc->textView1; doc.textStorage = doc->textView1.textStorage;
    doc->textView1.string = @"\\documentclass{article}";
    ScrapTextView *scrap = [[ScrapTextView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    InstallTextView(scrap, MakeScrollView(experiment));
    scrap.document = doc;
    scrap.richText = NO;  // as tryScrap: sets it
    [experiment makeFirstResponder:scrap];
    doc->scrapTextView = scrap;

    // Before the Experiment window is shown, nothing is colored.
    NSMutableString *source = [NSMutableString stringWithString:@"\\section{Top} % first comment\nplain text\n"];
    for (int i = 0; i < 80; i++) [source appendFormat:@"line %d\n", i];
    [source appendString:@"\\bottom % last comment\n"];
    scrap.string = source;
    [doc observeExperimentSource];
    [doc colorizeExperimentSource];
    Check(Foreground(scrap, 0) == nil, "a hidden Experiment window is not colored");

    // Shown (tryScrap: observes and applies the display): the visible lines get the source colors.
    experiment.shown = YES;
    [doc observeExperimentSource];
    [doc syncExperimentSourceDisplay];
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
        [[Render(scrap.enclosingScrollView) representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:@(getenv("TS_EXPERIMENT_COLOR_PNG")) atomically:YES];
    }

    // The active line follows the insertion point, and the toggle applies to the Experiment source.
    [doc toggleSyntaxColorEntry:Item(0)];
    Check(doc.syntaxcolorEntry, "active line coloring is on");
    [scrap setSelectedRange:NSMakeRange(Find(scrap, @"plain"), 0)];
    SpinUntil(3, ^BOOL { return [Background(scrap, Find(scrap, @"plain")) isEqual:entryColor]; });
    Check([Background(scrap, Find(scrap, @"plain")) isEqual:entryColor], "the active line in the Experiment source is highlighted");
    [scrap setSelectedRange:NSMakeRange(Find(scrap, @"line 0"), 0)];
    SpinUntil(3, ^BOOL { return [Background(scrap, Find(scrap, @"line 0")) isEqual:entryColor] && Background(scrap, Find(scrap, @"plain")) == nil; });
    Check([Background(scrap, Find(scrap, @"line 0")) isEqual:entryColor] && Background(scrap, Find(scrap, @"plain")) == nil,
          "moving the insertion point moves the highlight");

    // Block Cursor: the cursor's color, and the active line again when it is turned off.
    [SUD setFloat:0 forKey:BlockCursorRKey]; [SUD setFloat:0.5 forKey:BlockCursorGKey]; [SUD setFloat:0 forKey:BlockCursorBKey];
    NSColor *blockColor = [NSColor colorWithCalibratedRed:0 green:0.5 blue:0 alpha:1];
    NSUInteger cursor = Find(scrap, @"line 0") + 2;
    [scrap setSelectedRange:NSMakeRange(cursor, 0)];
    SpinUntil(3, ^BOOL { return [Background(scrap, Find(scrap, @"line 0")) isEqual:entryColor]; });
    [doc toggleBlockCursor:Item(0)];
    // With the block on the left (BlockSideKey 0), it covers the character before the insertion point.
    Check(doc.blockCursor && [Background(scrap, cursor - 1) isEqual:blockColor] && Background(scrap, cursor - 2) == nil,
          "Block Cursor shows the block cursor in the Experiment source at once");
    [doc toggleBlockCursor:Item(0)];
    Check(!doc.blockCursor && [Background(scrap, cursor - 2) isEqual:entryColor], "Block Cursor off brings the active line back");

    [doc toggleSyntaxColorEntry:Item(0)];
    Check(!doc.syntaxcolorEntry && Background(scrap, Find(scrap, @"line 0")) == nil, "turning active line coloring off removes the highlight");

    // The document's own source is still colored by the same code.
    [doc colorizeAll];
    Check([Foreground(doc->textView1, 0) isEqual:commandColor], "the document source is colored as before");

    // Index color, from the toolbar.
    [scrap insertText:@"\\index{key} " replacementRange:NSMakeRange(0, 0)];
    [doc flipIndexColor:0];
    Check([Foreground(scrap, Find(scrap, @"key")) isEqual:indexColor], "the index color appears in the Experiment source at once");
    NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect]; box.state = NSControlStateValueOff;
    [doc showIndexColor:box];
    Check(![Foreground(scrap, Find(scrap, @"key")) isEqual:indexColor], "turning the index color off removes it from the Experiment source");

    // Font, tabs and line spacing, from Settings.
    [SUD setBool:YES forKey:SaveDocumentFontKey];
    NSFont *settingsFont = [NSFont fontWithName:@"Menlo" size:15];
    [SUD setObject:[NSArchiver archivedDataWithRootObject:settingsFont] forKey:DocumentFontKey];
    [SUD setInteger:3 forKey:tabsKey];
    [SUD setFloat:3.0 forKey:SourceInterlineSpaceKey];
    [doc setDocumentFontFromPreferences:nil];
    NSParagraphStyle *scrapStyle = [scrap.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    Check([scrap.font.fontName isEqual:@"Menlo-Regular"] && scrap.font.pointSize == 15, "the document font applies to the Experiment source");
    Check(scrapStyle.lineSpacing == 3.0 && scrap.defaultParagraphStyle.lineSpacing == 3.0, "line spacing applies to the Experiment source");
    // Stored values outside the Settings ranges apply as the Settings fields show them.
    [SUD setInteger:2 forKey:tabsKey];
    [doc setDocumentFontFromPreferences:nil];
    NSArray *twoCharacterStops = doc->textView1.defaultParagraphStyle.tabStops;
    [SUD setInteger:0 forKey:tabsKey];
    [SUD setDouble:45 forKey:SourceInterlineSpaceKey];
    [SUD setDouble:150 forKey:SourceHeadIndentKey];
    [SUD setDouble:2.7 forKey:SourceFirstLineHeadIndentKey];
    [doc setDocumentFontFromPreferences:nil];
    NSParagraphStyle *ranged = doc->textView1.defaultParagraphStyle;
    Check(ranged.lineSpacing == 20 && ranged.headIndent == 100 && ranged.firstLineHeadIndent == 2 && [ranged.tabStops isEqual:twoCharacterStops],
          "out-of-range stored values apply at the nearest whole number of the Settings ranges");
    [SUD setDouble:0 forKey:SourceInterlineSpaceKey];
    [doc setDocumentFontFromPreferences:nil];
    Check(doc->textView1.defaultParagraphStyle.lineSpacing == 1, "line spacing 0 from an older version applies as 1");
    [SUD setInteger:3 forKey:tabsKey];
    [SUD setFloat:3.0 forKey:SourceInterlineSpaceKey];
    [SUD setDouble:0 forKey:SourceHeadIndentKey];
    [SUD setDouble:0 forKey:SourceFirstLineHeadIndentKey];
    [doc setDocumentFontFromPreferences:nil];
    scrapStyle = [scrap.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    Check([scrapStyle.tabStops isEqual:doc->textView1.defaultParagraphStyle.tabStops] && scrapStyle.tabStops.count > 0,
          "tab stops of the Experiment source are the document's");
    Check([scrap.typingAttributes[NSFontAttributeName] isEqual:scrap.font], "typed text gets the document font");

    // Wrapping, from the Source menu.
    scrap.string = @"short\nline\n";
    [doc setLineBreakMode:Item(0)];
    Check(!scrap.textContainer.widthTracksTextView && scrap.isHorizontallyResizable && scrap.enclosingScrollView.hasHorizontalScroller &&
          scrap.defaultParagraphStyle.lineBreakMode == NSLineBreakByClipping, "No Wrap applies to the Experiment source");
    NSString *longLine = [@"" stringByPaddingToLength:300 withString:@"word " startingAtIndex:0];
    [scrap insertText:longLine replacementRange:NSMakeRange(scrap.string.length, 0)];
    Check(OnOneLine(scrap, NSMakeRange(Find(scrap, longLine), longLine.length)), "with No Wrap, a long line stays on one line");
    [scrap insertText:@"" replacementRange:NSMakeRange(Find(scrap, longLine), longLine.length)];
    [doc setLineBreakMode:Item(2)];
    [scrap insertText:longLine replacementRange:NSMakeRange(scrap.string.length, 0)];
    Check(scrap.textContainer.widthTracksTextView && !scrap.isHorizontallyResizable && !scrap.enclosingScrollView.hasHorizontalScroller &&
          scrap.defaultParagraphStyle.lineBreakMode == NSLineBreakByCharWrapping, "Wrap by Character applies to the Experiment source");
    Check(!OnOneLine(scrap, NSMakeRange(Find(scrap, longLine), longLine.length)), "after No Wrap, a long line wraps again");
    [doc setLineBreakMode:Item(1)];
    Check(scrap.defaultParagraphStyle.lineBreakMode == NSLineBreakByWordWrapping, "Wrap by Word applies to the Experiment source");

    // A font chosen in the Experiment source (Font panel, Bigger, Smaller) is the document's font too.
    PanelFont = [NSFont fontWithName:@"Menlo" size:24];
    method_setImplementation(class_getInstanceMethod(NSFontManager.class, @selector(convertFont:)), (IMP)PanelConvertFont);
    [scrap changeFont:[NSFontManager sharedFontManager]];
    Check(scrap.font.pointSize == 24 && doc->textView1.font.pointSize == 24,
          "a font chosen in the Experiment source becomes the document's font");
    [doc setLineBreakMode:Item(1)];
    Check(scrap.font.pointSize == 24 && [scrap.typingAttributes[NSFontAttributeName] pointSize] == 24 &&
          scrap.defaultParagraphStyle.defaultTabInterval == doc->textView1.defaultParagraphStyle.defaultTabInterval &&
          scrap.defaultParagraphStyle.defaultTabInterval > 0,
          "the Experiment source keeps that font and the document's tabs after another setting changes");
    [doc setDocumentFontFromPreferences:nil];
    Check(scrap.font.pointSize == 15, "the Settings font applies again to both");

    // XML coloring, from the Source menu.
    scrap.string = @"<tag>text</tag>\n";
    NSMenuItem *xmlItem = Item(0); xmlItem.state = NSControlStateValueOff;
    [doc toggleXML:xmlItem];
    Check(doc.fileIsXML && [Foreground(scrap, 1) isEqual:XMLColor], "XML coloring applies to the Experiment source at once");
    [doc toggleXML:xmlItem];
    Check(!doc.fileIsXML && ![Foreground(scrap, 1) isEqual:XMLColor], "turning XML coloring off applies to the Experiment source at once");

    // Invisible characters, from the Source menu; the kinds come from Settings.
    for (NSString *key in @[showSpaceCharacterKey, showTabCharacterKey, showNewLineCharacterKey, showFullwidthSpaceCharacterKey])
        [SUD setBool:YES forKey:key];
    scrap.string = @"a b\tc\n";
    Check(MarkersDrawn(scrap) == 0, "no invisible characters before they are shown");
    [doc showHideInvisibleCharacters:nil];
    Check([scrap.layoutManager isKindOfClass:TSLayoutManager.class] && MarkersDrawn(scrap) >= 3,
          "Show Invisible Characters applies to the Experiment source");
    [doc showHideInvisibleCharacters:nil];
    Check(MarkersDrawn(scrap) == 0, "hiding invisible characters applies to the Experiment source");

    // Line numbers, from the Source menu.
    [doc showHideLineNumbers:nil];
    NSScrollView *scrapScroll = scrap.enclosingScrollView;
    Check(scrapScroll.rulersVisible && [scrapScroll.verticalRulerView isKindOfClass:NoodleLineNumberView.class] &&
          scrapScroll.verticalRulerView.clientView == scrap, "Show Line Numbers applies to the Experiment source");
    [doc showHideInvisibleCharacters:nil];
    if (getenv("TS_EXPERIMENT_DISPLAY_PNG")) {
        scrap.string = @"\\section{Experiment} % comment\n\tA b\u3000c\n\\frac{1}{2}\n";
        [doc colorizeExperimentSource];
        [[Render(scrapScroll) representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:@(getenv("TS_EXPERIMENT_DISPLAY_PNG")) atomically:YES];
    }

    // Opening the Experiment window again applies everything to a new view.
    TestWindow *second = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    second.releasedWhenClosed = NO; second.shown = YES;
    ScrapTextView *fresh = [[ScrapTextView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    InstallTextView(fresh, MakeScrollView(second));
    fresh.string = @"\\fresh a b\n";
    doc->scrapTextView = fresh;
    [doc syncExperimentSourceDisplay];
    Check([fresh.font.fontName isEqual:@"Menlo-Regular"] && fresh.enclosingScrollView.rulersVisible && MarkersDrawn(fresh) >= 2 &&
          [Foreground(fresh, 0) isEqual:commandColor], "a new Experiment source gets the font, line numbers, invisible characters and colors");
    doc->scrapTextView = scrap;
    [doc showHideInvisibleCharacters:nil];
    [doc showHideLineNumbers:nil];
    Check(!scrapScroll.rulersVisible, "hiding line numbers applies to the Experiment source");

    // Brace matching when the insertion point moves over a brace.
    for (NSString *key in @[CheckBraceEnabledKey, CheckParenEnabledKey, CheckSquareBracketEnabledKey, HighlightContentEnabledKey,
                            ShowIndicatorForMoveEnabledKey, FlashBackgroundEnabledKey])
        [SUD setBool:YES forKey:key];
    scrap.string = @"\\frac{ab}{cd} x";
    Spin(0.02);
    NSUInteger close = Find(scrap, @"}"), open = Find(scrap, @"{");
    [scrap setSelectedRange:NSMakeRange(close, 0)];
    Spin(0.02);
    [indicators removeAllObjects];
    [scrap setSelectedRange:NSMakeRange(close + 1, 0)];
    Spin(0.05);
    Check([Foreground(scrap, open) isEqual:braceColor] && [Foreground(scrap, close) isEqual:braceColor],
          "moving past a brace in the Experiment source highlights the pair");
    Check([Background(scrap, open + 1) isEqual:contentColor], "the content between the braces is highlighted");
    Check([indicators containsObject:[@"experiment " stringByAppendingString:NSStringFromRange(NSMakeRange(open, 1))]],
          "the partner is shown in the Experiment source");
    Check(doc->scrapBraceHighlighting && !doc->braceHighlighting, "the Experiment source keeps its own brace state");
    Spin(0.4);
    Check(![Foreground(scrap, open) isEqual:braceColor] && !doc->scrapBraceHighlighting, "the brace highlight goes away");

    // An unmatched brace flashes the background of the Experiment source.
    scrap.string = @"ab} x";
    Spin(0.02);
    [scrap setSelectedRange:NSMakeRange(2, 0)];
    Spin(0.02);
    [scrap setSelectedRange:NSMakeRange(3, 0)];
    Spin(0.05);
    Check([scrap.backgroundColor isEqual:FlashColor] && ![doc->textView1.backgroundColor isEqual:FlashColor],
          "an unmatched brace flashes the Experiment source");
    Spin(0.3);
    Check([scrap.backgroundColor isEqual:ThemeBackground], "the theme's background comes back after the flash");

    // The document's source keeps its own brace matching.
    doc->textView1.string = @"{ab} y";
    [doc->textView1 setSelectedRange:NSMakeRange(3, 0)];
    [doc textViewDidChangeSelection:nil];
    [doc->textView1 setSelectedRange:NSMakeRange(4, 0)];
    [doc textViewDidChangeSelection:nil];
    Spin(0.05);
    Check([Foreground(doc->textView1, 0) isEqual:braceColor] && doc->braceHighlighting && !doc->scrapBraceHighlighting,
          "brace matching in the document's source is unchanged");
    Spin(0.4);

    // Typing a closing brace shows its partner.
    [SUD setBool:NO forKey:ShowIndicatorForMoveEnabledKey];
    [SUD setBool:YES forKey:ParensMatchingEnabledKey];
    [SUD setBool:YES forKey:brieflyFlashYellowForMatchKey];
    scrap.string = @"(ab";
    [scrap setSelectedRange:NSMakeRange(3, 0)];
    Spin(0.02);
    [indicators removeAllObjects];
    [scrap insertText:@")" replacementRange:scrap.selectedRange];
    Spin(0.02);
    Check([indicators isEqual:@[[@"experiment " stringByAppendingString:NSStringFromRange(NSMakeRange(0, 1))]]],
          "typing a closing parenthesis shows the opening one");
    [SUD setBool:NO forKey:brieflyFlashYellowForMatchKey];
    scrap.string = @"[ab";
    [scrap setSelectedRange:NSMakeRange(3, 0)];
    [flashSelections removeAllObjects];
    [scrap insertText:@"]" replacementRange:scrap.selectedRange];
    Check([flashSelections containsObject:NSStringFromRange(NSMakeRange(0, 1))] && [scrap.string isEqual:@"[ab]"],
          "typing a closing bracket briefly selects the opening one");

    if (failures) return 1;
    printf("PASS: the Experiment source follows the document's colors, active line, block cursor, index color, font, "
           "wrapping, invisible characters, line numbers and brace matching\n");
} return 0; }
'''
replacements = {
    'DEFINES': defines, 'SCRAP_OVERRIDES': scrap_overrides, 'TAB_STOPS': tab_stops, 'BRACE_SEARCH': brace_search,
    'DOCUMENT_METHODS': document_methods, 'TOGGLE_XML': toggle_xml, 'TEXT_VIEW_TABS': text_view_tabs, 'SYNTAX': strip_imports(text[SYNTAX]), 'EXPERIMENT': strip_imports(text[EXPERIMENT]),
    'TRY_SCRAP_SYNCS': 'YES' if '[self syncExperimentSourceDisplay];' in try_scrap else 'NO',
}
for name, value in replacements.items():
    program = program.replace(f'@@{name}@@', value)

with tempfile.TemporaryDirectory(prefix='texshop-experiment-display-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    (tmp / 'keys.m').write_text('#import <Cocoa/Cocoa.h>\n' + marker_keys + '\nNSColor *InvisibleColor;\nBOOL atLeastMonterey = YES, atLeastSonoma = YES;\n', encoding='latin1')
    sources = [tmp / 'probe.m', tmp / 'keys.m', source_file(root, 'TSLayoutManager.m'), source_file(root, 'TSAdvancedFindHighlights.m'), source_file(root, 'NoodleLineNumberView.m'),
               source_file(root, 'NoodleLineNumberMarker.m'), source_file(root, 'NSText-Extras.m'),
               *sorted((root / 'Sources/Syntax').glob('*.m')), source_file(root, 'TSMacroContentKind.m')]
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *include_args(root),
                    '-I', str(root / 'Tests'), *map(str, sources), '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=120)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
