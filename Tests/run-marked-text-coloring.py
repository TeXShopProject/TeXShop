#!/usr/bin/env python3
"""Text being composed with an input method (marked text) is not colored.

While Japanese is typed, every keystroke changes the composed text, and with the
layout of long documents it also resizes the source. Nothing is colored then: not
the composed text, so that a fullwidth digit being typed gets no highlight, and not
the visible text, which would otherwise be recolored at every keystroke. What
waited is colored once the composed text is committed or removed, in either half of
a split window and in the Experiment source; a brace highlight stays while text is
composed, and it and the active line follow afterwards.

The production categories TSDocument (SyntaxHighlighting) and TSDocument
(ExperimentSource) are compiled unchanged onto a small TSDocument stand-in, with the
production TSDocument methods for brace matching, the overrides of ScrapTextView and
the real TSLayoutManager, laying out only what is needed as the source does. Text is
composed through the NSTextInputClient methods that input methods call. Windows are
never ordered on screen. Preferences stay in memory."""
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
    'no-colorize-wait': (SYNTAX,
        '    if ([self coloringWaitsForMarkedTextIn:aTextView])\n        return;\n\n    colorExpl3', '    colorExpl3'),
    'no-visible-area-wait': (SYNTAX,
        '    if ([self coloringWaitsForMarkedTextIn:aTextView])\n        return;\n    \n    // Nov 5, 2024. Koch.', '    \n    // Nov 5, 2024. Koch.'),
    'no-active-line-wait': (SYNTAX,
        'if (self.syntaxcolorEntry && ![self coloringWaitsForMarkedTextIn:aTextView])', 'if (self.syntaxcolorEntry)'),
    'wait-only-in-this-view': (SYNTAX,
        '    if (!aTextView || !TSTextStorageHasMarkedText(aTextView.textStorage))', '    if (!aTextView.hasMarkedText)'),
    'no-color-after-selection': (DOCUMENT,
        '\t[self colorAfterMarkedTextEnds];\n\t[self matchBracesForSelectionInTextView:nil];', '\t[self matchBracesForSelectionInTextView:nil];'),
    'no-experiment-color-after-selection': (EXPERIMENT,
        '    [self colorAfterMarkedTextEnds];\n    if ([self experimentSourceShown])', '    if ([self experimentSourceShown])'),
    'color-while-source-composes': (SYNTAX,
        '    if (!self.coloringWaitsForMarkedText || TSTextStorageHasMarkedText(self.textStorage) ||', '    if (!self.coloringWaitsForMarkedText ||'),
    'color-while-experiment-composes': (SYNTAX,
        ' ||\n        (scrapTextView.window.isVisible && TSTextStorageHasMarkedText(scrapTextView.textStorage)))\n        return;', ')\n        return;'),
    'closed-experiment-holds-source': (SYNTAX,
        '(scrapTextView.window.isVisible && TSTextStorageHasMarkedText(scrapTextView.textStorage))', '(scrapTextView && TSTextStorageHasMarkedText(scrapTextView.textStorage))'),
    'brace-reset-before-wait': (DOCUMENT,
        '    if ([self coloringWaitsForMarkedTextIn:textView])\n        return;\n    \n  // item added by Koch in August, 2018',
        '  // item added by Koch in August, 2018'),
    'no-active-line-after-commit': (SYNTAX,
        '    [self colorizeAll];\n    [self cursorMoved:textView];\n    [self refreshExperimentCurrentLine];\n}',
        '    [self colorizeAll];\n    [self refreshExperimentCurrentLine];\n}'),
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
- (void)fixColor:(NSUInteger)from :(NSUInteger)to;
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

// Every change of a color in temporary attributes, and every look-up of the visible
// text. AppKit itself keeps other temporary attributes, for text checking.
static NSUInteger attributeChanges, visibleLookups;
static void (*originalAdd)(id, SEL, NSDictionary *, NSRange);
static void (*originalRemove)(id, SEL, NSString *, NSRange);
static NSRange (*originalGlyphRange)(id, SEL, NSRect, NSTextContainer *);
static BOOL IsColor(NSString *name) { return [name isEqual:NSForegroundColorAttributeName] || [name isEqual:NSBackgroundColorAttributeName]; }
static void Trace(const char *what, NSRange range)
{
    if (!getenv("TS_TRACE")) return;
    printf("%s %s\n", what, NSStringFromRange(range).UTF8String);
    NSArray *stack = NSThread.callStackSymbols;
    for (NSUInteger i = 2; i < MIN(stack.count, 8); i++) printf("   %s\n", [stack[i] UTF8String]);
}
static void CountAdd(NSLayoutManager *layout, SEL cmd, NSDictionary *attributes, NSRange range)
{
    for (NSString *name in attributes) if (IsColor(name)) { attributeChanges++; Trace("add", range); break; }
    originalAdd(layout, cmd, attributes, range);
}
static void CountRemove(NSLayoutManager *layout, SEL cmd, NSString *name, NSRange range)
{
    if (IsColor(name)) { attributeChanges++; Trace("remove", range); }
    originalRemove(layout, cmd, name, range);
}
static NSRange CountGlyphRange(NSLayoutManager *layout, SEL cmd, NSRect rect, NSTextContainer *container) { visibleLookups++; return originalGlyphRange(layout, cmd, rect, container); }
static void Swap(SEL selector, IMP replacement, void *original)
{
    Method m = class_getInstanceMethod(NSLayoutManager.class, selector);
    *(IMP *)original = method_getImplementation(m);
    method_setImplementation(m, replacement);
}

static NSScrollView *MakeScrollView(NSWindow *window) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    scroll.hasVerticalScroller = YES;
    window.contentView = scroll;
    return scroll;
}
// As -[TSTextView awakeFromNib]: TSLayoutManager, laying out only what is needed.
static void InstallTextView(NSTextView *view, NSScrollView *scroll) {
    view.verticallyResizable = YES; view.autoresizingMask = NSViewWidthSizable;
    view.textContainer.widthTracksTextView = YES;
    view.font = [NSFont userFixedPitchFontOfSize:12];
    TSLayoutManager *layout = [TSLayoutManager new];
    layout.allowsNonContiguousLayout = YES;
    [view.textContainer replaceLayoutManager:layout];
    scroll.documentView = view;
}
static NSColor *Foreground(NSTextView *view, NSUInteger index) {
    return [view.layoutManager temporaryAttributesAtCharacterIndex:index effectiveRange:NULL][NSForegroundColorAttributeName];
}
static NSColor *Background(NSTextView *view, NSUInteger index) {
    return [view.layoutManager temporaryAttributesAtCharacterIndex:index effectiveRange:NULL][NSBackgroundColorAttributeName];
}
static NSUInteger Find(NSTextView *view, NSString *text) { return [view.string rangeOfString:text].location; }
static void Uncolor(NSTextView *view) {
    NSRange all = NSMakeRange(0, view.string.length);
    [view.layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:all];
    [view.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:all];
}
static NSUInteger frameChanges;
@interface FrameCounter : NSObject
@end
@implementation FrameCounter
- (void)changed:(NSNotification *)notification { frameChanges++; }
@end
// Typing with an input method: the composed text grows one keystroke at a time.
static void Compose(NSTextView *view, NSArray<NSString *> *steps) {
    for (NSString *step in steps) {
        [view setMarkedText:step selectedRange:NSMakeRange(step.length, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        [view.window displayIfNeeded];
        Spin(0.01);
    }
}
static NSMutableString *Source(void) {
    NSMutableString *source = [NSMutableString stringWithString:@"\\section{Top} % first comment\n"];
    for (int i = 0; i < 400; i++)
        [source appendFormat:@"\\textbf{%d} \u672c\u6587\u306e\u884c\u3067\u3059\u3002\u3053\u308c\u306f\u9577\u3044\u65e5\u672c\u8a9e\u306e\u6bb5\u843d\u3067\u3001\u6298\u308a\u8fd4\u3057\u304c\u8d77\u304d\u308b\u3088\u3046\u306b\u5c11\u3057\u9577\u3081\u306b\u3057\u3066\u3042\u308a\u307e\u3059\u3002\n", i];
    return source;
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    indicators = [NSMutableArray array]; flashSelections = [NSMutableArray array];
    FlashColor = NSColor.orangeColor; ThemeBackground = NSColor.whiteColor; XMLColor = NSColor.brownColor;
    NSColor *commandColor = NSColor.blueColor, *commentColor = NSColor.redColor, *entryColor = NSColor.yellowColor;
    NSColor *braceColor = NSColor.magentaColor, *fullwidthColor = NSColor.purpleColor, *fullwidthBackground = NSColor.darkGrayColor;
    highlightBracesColorDict = @{NSForegroundColorAttributeName: braceColor};
    highlightContentColorDict = @{NSBackgroundColorAttributeName: NSColor.cyanColor};
    TSDocument *doc = [TSDocument new];
    NSDictionary *plain = @{NSForegroundColorAttributeName: NSColor.textColor};
    for (NSString *key in @[@"explColorAttribute1", @"explColorAttribute2", @"explColorAttribute3", @"explColorAttribute4",
                            @"explColorAttribute5", @"explColorAttribute6", @"explColorAttribute7", @"footnoteColorAttribute",
                            @"markerColorAttribute", @"markerColorCurlyAttribute", @"indexColorAttribute",
                            @"markerColorParenAttribute", @"markerColorSquareAttribute", @"regularColorAttribute"])
        [doc setValue:plain forKey:key];
    doc.commandColorAttribute = @{NSForegroundColorAttributeName: commandColor};
    doc.commentColorAttribute = @{NSForegroundColorAttributeName: commentColor};
    doc.EntryColorAttribute = @{NSBackgroundColorAttributeName: entryColor};
    doc.fullwidthSymbolColorAttribute = @{NSForegroundColorAttributeName: fullwidthColor, NSBackgroundColorAttributeName: fullwidthBackground};
    doc.syntaxColor = YES; doc->fileIsTex = YES; doc->lineBreakMode = NSLineBreakByWordWrapping;

    // The document's window, never ordered on screen, split in two halves showing the same text.
    TestWindow *mainWindow = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    TestWindow *lowerWindow = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    mainWindow.releasedWhenClosed = NO; lowerWindow.releasedWhenClosed = NO;
    doc->scrollView = MakeScrollView(mainWindow);
    doc->scrollView2 = MakeScrollView(lowerWindow);
    doc.logScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    doc->textView1 = [[TestSourceView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    doc->textView2 = [[TestSourceView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    InstallTextView(doc->textView1, doc->scrollView);
    InstallTextView(doc->textView2, doc->scrollView2);
    doc.textView = doc->textView1; doc.textStorage = doc->textView1.textStorage;
    [doc->textView2.layoutManager replaceTextStorage:doc.textStorage];
    doc->textView1.delegate = (id)doc; doc->textView2.delegate = (id)doc;
    doc->windowIsSplit = YES;
    [mainWindow makeFirstResponder:doc->textView1];
    NSTextView *source = doc->textView1, *lower = doc->textView2;
    // As -[TSDocument windowControllerDidLoadNib:]: scrolling and resizing recolor.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSScrollView *scroll in @[doc->scrollView, doc->scrollView2]) {
        scroll.contentView.postsBoundsChangedNotifications = YES;
        [center addObserver:doc selector:@selector(viewBoundsDidChange:) name:NSViewBoundsDidChangeNotification object:scroll.contentView];
    }
    FrameCounter *counter = [FrameCounter new];
    for (NSTextView *view in @[source, lower]) {
        view.postsFrameChangedNotifications = YES;
        [center addObserver:doc selector:@selector(viewFrameDidChange:) name:NSViewFrameDidChangeNotification object:view];
        [center addObserver:counter selector:@selector(changed:) name:NSViewFrameDidChangeNotification object:view];
    }

    source.string = Source();
    [doc colorizeAll];
    Check([Foreground(source, 0) isEqual:commandColor] && [Foreground(lower, 0) isEqual:commandColor], "both halves of the source are colored");
    NSUInteger line = Find(source, @"\\textbf{1}");
    NSUInteger at = line + @"\\textbf{1} \u672c\u6587\u306e".length;
    [source setSelectedRange:NSMakeRange(at, 0)];
    [mainWindow displayIfNeeded];
    Spin(0.05);

    Swap(@selector(addTemporaryAttributes:forCharacterRange:), (IMP)CountAdd, &originalAdd);
    Swap(@selector(removeTemporaryAttribute:forCharacterRange:), (IMP)CountRemove, &originalRemove);
    Swap(@selector(glyphRangeForBoundingRect:inTextContainer:), (IMP)CountGlyphRange, &originalGlyphRange);

    // Composing a fullwidth digit and more: nothing is colored, and the composed text keeps no color.
    attributeChanges = 0; visibleLookups = 0; frameChanges = 0;
    Compose(source, @[@"\uff11", @"\uff11\uff12", @"\uff11\uff12\uff4b", @"\uff11\uff12\u304b", @"\uff11\uff12\u304b\u3044", @"\uff11\uff12\u304b\u3044\uff4d", @"\uff11\uff12\u304b\u3044\u3081"]);
    Check(source.hasMarkedText, "the text is being composed");
    Check(frameChanges > 0, "composing resizes the source, as it does with the layout of long documents");
    Check(attributeChanges == 0, "composing changes no colors");
    Check(Foreground(source, at) == nil && Background(source, at) == nil, "the composed fullwidth digit has no color");
    Check(doc.coloringWaitsForMarkedText, "coloring waits for the composed text");

    // Scrolling, resizing, recoloring after a theme change and the edit routines wait too,
    // without looking up the visible text.
    visibleLookups = 0;
    [doc viewFrameDidChange:[NSNotification notificationWithName:NSViewFrameDidChangeNotification object:source]];
    [doc viewBoundsDidChange:[NSNotification notificationWithName:NSViewBoundsDidChangeNotification object:doc->scrollView2.contentView]];
    [doc colorizeAll];
    [doc fixColor:line :at + 2];
    [doc cursorMoved:source];
    Check(attributeChanges == 0 && visibleLookups == 0, "resizing, scrolling, recoloring and edits do not color composed text");

    // Committing colors the visible text once, the committed fullwidth digit included.
    [source insertText:@"\uff11\uff12\u56de\u76ee" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check(!source.hasMarkedText && !doc.coloringWaitsForMarkedText, "nothing waits after the text is committed");
    Check([Foreground(source, at) isEqual:fullwidthColor] && [Background(source, at) isEqual:fullwidthBackground],
          "the committed fullwidth digit is highlighted");
    Check([Foreground(source, line) isEqual:commandColor] && [Foreground(lower, line) isEqual:commandColor], "both halves are colored after the commit");

    // Removing the composed text (Escape) also colors what waited.
    Uncolor(source); Uncolor(lower);
    [source setSelectedRange:NSMakeRange(at, 0)];
    Compose(source, @[@"\uff4b", @"\u304b"]);
    [doc colorizeAll];
    Check(Foreground(source, 0) == nil, "recoloring waits while composing");
    [source setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check(!doc.coloringWaitsForMarkedText && [Foreground(source, 0) isEqual:commandColor] && [Foreground(lower, 0) isEqual:commandColor],
          "removing the composed text colors what waited");
    [source unmarkText];
    Compose(source, @[@"\uff53", @"\u3055"]);
    [doc colorizeAll];
    Uncolor(source);
    [source unmarkText];
    Spin(0.05);
    Check([Foreground(source, 0) isEqual:commandColor], "unmarking the composed text colors what waited");

    // The active line is not redrawn while composing, and follows afterwards.
    doc.syntaxcolorEntry = YES;
    [source setSelectedRange:NSMakeRange(Find(source, @"\\textbf{2}") + 10, 0)];
    [doc cursorMoved:source];
    Check([Background(source, Find(source, @"\\textbf{2}")) isEqual:entryColor], "the active line is highlighted");
    attributeChanges = 0;
    Compose(source, @[@"\uff54", @"\u305f"]);
    [doc cursorMoved:source];
    Check(attributeChanges == 0, "the active line is not redrawn while composing");
    [source insertText:@"\u305f" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check([Background(source, Find(source, @"\\textbf{2}")) isEqual:entryColor], "the active line is highlighted after the commit");
    // With Syntax Color off, the active line follows the commit too.
    doc.syntaxColor = NO;
    NSUInteger fourth = Find(source, @"\\textbf{4}");
    [source setSelectedRange:NSMakeRange(fourth + 10, 0)];
    Compose(source, @[@"\uff54"]);
    [doc cursorMoved:source];  // as -[TSTextView updateInsertionPointStateAndRestartTimer:] does
    [source insertText:@"\uff54" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check([Background(source, fourth) isEqual:entryColor] && Background(source, Find(source, @"\\textbf{2}")) == nil,
          "with Syntax Color off, the active line follows the commit");
    doc.syntaxColor = YES;
    doc.syntaxcolorEntry = NO;
    [doc removeCurrentLineColor:source];

    // A brace highlight stays while composing, and goes once the text is committed.
    for (NSString *key in @[CheckBraceEnabledKey, AlwaysHighlightEnabledKey]) [SUD setBool:YES forKey:key];
    NSUInteger open = Find(source, @"\\textbf{3}") + 7, close = open + 2;
    // The lower half shows the end of the text, so that recoloring what is visible there
    // does not remove the highlight by itself.
    [lower scrollRangeToVisible:NSMakeRange(lower.string.length, 0)];
    [source setSelectedRange:NSMakeRange(close, 0)];
    Spin(0.05);
    [source setSelectedRange:NSMakeRange(close + 1, 0)];
    Spin(0.05);
    Check(doc->braceHighlighting && [Foreground(source, open) isEqual:braceColor] && [Foreground(lower, open) isEqual:braceColor],
          "moving past a brace highlights the pair in both halves");
    attributeChanges = 0;
    Compose(source, @[@"\uff4e", @"\u306a"]);
    Spin(0.05);
    Check(attributeChanges == 0 && doc->braceHighlighting && [Foreground(source, open) isEqual:braceColor],
          "the brace highlight is not removed while composing");
    [source insertText:@"\u306a" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check(!doc->braceHighlighting && ![Foreground(source, open) isEqual:braceColor] && [Foreground(source, open - 7) isEqual:commandColor],
          "after the commit the brace highlight goes and the colors come back");
    Check(![Foreground(lower, open) isEqual:braceColor], "the brace highlight also goes from the lower half");
    for (NSString *key in @[CheckBraceEnabledKey, AlwaysHighlightEnabledKey]) [SUD setBool:NO forKey:key];

    // Text composed in the lower half waits too.
    [lowerWindow makeFirstResponder:lower];
    [lower setSelectedRange:NSMakeRange(at, 0)];
    attributeChanges = 0;
    Compose(lower, @[@"\uff21"]);
    [doc colorizeAll];
    Check(attributeChanges == 0 && doc.coloringWaitsForMarkedText, "text composed in the lower half waits as well");
    [lower insertText:@"\uff21" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check([Foreground(lower, at) isEqual:fullwidthColor] && !doc.coloringWaitsForMarkedText, "the lower half is colored after the commit");

    // The Experiment source.
    TestWindow *experiment = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    experiment.releasedWhenClosed = NO; experiment.shown = YES;
    ScrapTextView *scrap = [[ScrapTextView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    InstallTextView(scrap, MakeScrollView(experiment));
    scrap.document = doc; scrap.richText = NO;
    [experiment makeFirstResponder:scrap];
    doc->scrapTextView = scrap;
    scrap.string = Source();
    [doc observeExperimentSource];
    [doc syncExperimentSourceDisplay];
    Check([Foreground(scrap, 0) isEqual:commandColor], "the Experiment source is colored");
    NSUInteger scrapAt = Find(scrap, @"\\textbf{1} \u672c\u6587") + 10;
    [scrap setSelectedRange:NSMakeRange(scrapAt, 0)];
    Spin(0.05);
    attributeChanges = 0;
    Compose(scrap, @[@"\uff11", @"\uff11\uff4b", @"\uff11\u304b"]);
    visibleLookups = 0;
    [doc colorizeExperimentSource];
    Check(attributeChanges == 0 && visibleLookups == 0 && Foreground(scrap, scrapAt) == nil,
          "composing in the Experiment source changes no colors");
    [scrap insertText:@"\uff11\u304b" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check([Foreground(scrap, scrapAt) isEqual:fullwidthColor] && !doc.coloringWaitsForMarkedText,
          "the Experiment source is colored after the commit");
    // Composing in one source colors nothing in the other one either.
    [mainWindow makeFirstResponder:source];
    [source setSelectedRange:NSMakeRange(at, 0)];
    Spin(0.05);
    attributeChanges = 0;
    Compose(source, @[@"\uff4b", @"\u304b"]);
    Spin(0.05);
    Check(attributeChanges == 0, "composing in the source does not color the Experiment source");
    [source insertText:@"\u304b" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    [scrap setSelectedRange:NSMakeRange(scrapAt, 0)];
    Spin(0.05);
    attributeChanges = 0;
    Compose(scrap, @[@"\uff4b", @"\u304b"]);
    Spin(0.05);
    Check(attributeChanges == 0, "composing in the Experiment source does not color the source");
    [scrap insertText:@"\u304b" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Uncolor(scrap);
    Compose(scrap, @[@"\uff4b"]);
    [doc colorizeExperimentSource];
    [scrap setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check([Foreground(scrap, 0) isEqual:commandColor], "removing text composed in the Experiment source colors what waited");

    // Text left composed in a closed Experiment window does not hold back the source,
    // and waits again when the window is shown.
    [scrap setSelectedRange:NSMakeRange(scrapAt, 0)];
    Compose(scrap, @[@"\uff4b", @"\u304b"]);
    [doc colorizeExperimentSource];
    Check(doc.coloringWaitsForMarkedText, "text composed in the Experiment source waits");
    experiment.shown = NO;
    [mainWindow makeFirstResponder:source];
    [source setSelectedRange:NSMakeRange(at, 0)];
    Uncolor(source);
    Compose(source, @[@"\uff53", @"\u3055"]);
    [doc colorizeAll];
    [source insertText:@"\u3055" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check(scrap.hasMarkedText && !doc.coloringWaitsForMarkedText && [Foreground(source, 0) isEqual:commandColor],
          "text left composed in a closed Experiment window does not hold back the source");
    experiment.shown = YES;
    Uncolor(scrap);
    [doc syncExperimentSourceDisplay];
    Check(Foreground(scrap, 0) == nil && doc.coloringWaitsForMarkedText, "shown again, the Experiment source waits for its composed text");
    [scrap insertText:@"\u304b" replacementRange:NSMakeRange(NSNotFound, 0)];
    Spin(0.05);
    Check(!doc.coloringWaitsForMarkedText && [Foreground(scrap, 0) isEqual:commandColor], "the Experiment source is colored after that text is committed");

    if (failures) return 1;
    printf("PASS: text composed with an input method is not colored, in either half of the source or in the Experiment "
           "source; what waited is colored once it is committed or removed\n");
} return 0; }
'''
replacements = {
    'DEFINES': defines, 'SCRAP_OVERRIDES': scrap_overrides, 'TAB_STOPS': tab_stops, 'BRACE_SEARCH': brace_search,
    'DOCUMENT_METHODS': document_methods, 'TOGGLE_XML': toggle_xml, 'TEXT_VIEW_TABS': text_view_tabs, 'SYNTAX': strip_imports(text[SYNTAX]), 'EXPERIMENT': strip_imports(text[EXPERIMENT]),
    'TRY_SCRAP_SYNCS': 'YES' if '[self syncExperimentSourceDisplay];' in try_scrap else 'NO',
}
for name, value in replacements.items():
    program = program.replace(f'@@{name}@@', value)

with tempfile.TemporaryDirectory(prefix='texshop-marked-text-coloring-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    (tmp / 'keys.m').write_text('#import <Cocoa/Cocoa.h>\n' + marker_keys + '\nNSColor *InvisibleColor;\nBOOL atLeastMonterey = YES, atLeastSonoma = YES;\n', encoding='latin1')
    sources = [tmp / 'probe.m', tmp / 'keys.m', source_file(root, 'TSLayoutManager.m'), source_file(root, 'NoodleLineNumberView.m'),
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
