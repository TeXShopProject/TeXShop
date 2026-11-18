#!/usr/bin/env python3
"""Brace highlights and the backgrounds of the source go away when they should, and only then.

- Moving past braces one after the other: the pair highlighted last stays for its own
  time, and the flash of the background for an unmatched brace too; the reset that an
  earlier pair or flash scheduled does nothing.
- A brace being composed with an input method is not highlighted; once committed it is,
  as a typed one. A reset that comes due while text is composed is done after the text
  is committed or removed, and the highlight is not given again.
- A line joined to a comment above it (its line break deleted) shows its fullwidth
  digits without their background, as the same text colored anew does.
- Coloring again (resizing, scrolling, a change of settings or theme) keeps the
  highlight of the braces and of their contents, over fullwidth characters too.
- When the highlight of the contents ends, the fullwidth characters have their
  background again, and other text keeps its own.

All this in either half of a split window and in the Experiment source, with "Flash"
and "Always" highlighting. The production categories TSDocument (SyntaxHighlighting) and
TSDocument (ExperimentSource) are compiled unchanged onto a small TSDocument stand-in,
with the production TSDocument methods for brace matching, the overrides of
ScrapTextView and the real TSLayoutManager. Text is composed through the
NSTextInputClient methods that input methods call. Windows are never ordered on
screen. Preferences stay in memory."""
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
    'no-highlight-generation': (DOCUMENT,
        '    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != braceHighlightGeneration)\n        return;\n', ''),
    'no-flash-generation': (DOCUMENT,
        '    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != braceFlashGeneration)\n        return;\n', ''),
    'no-experiment-highlight-generation': (EXPERIMENT,
        '    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != scrapBraceHighlightGeneration)\n        return;\n', ''),
    'no-experiment-flash-generation': (EXPERIMENT,
        '    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != scrapBraceFlashGeneration)\n        return;\n', ''),
    'highlights-composed-brace': (DOCUMENT, '    if ([selectionView hasMarkedText]) {', '    if (NO) {'),
    'keeps-braces-while-composing': (DOCUMENT,
        '    if ([self coloringWaitsForMarkedTextIn:textView]) {\n        highlightedBraceLocations = nil;\n', '    if ([self coloringWaitsForMarkedTextIn:textView]) {\n'),
    'keeps-experiment-braces-while-composing': (EXPERIMENT,
        '    if ([self coloringWaitsForMarkedTextIn:scrapTextView]) {\n        scrapHighlightedBraceLocations = nil;\n', '    if ([self coloringWaitsForMarkedTextIn:scrapTextView]) {\n'),
    'other-half-resets': (DOCUMENT,
        '\tif ([inNotification object] != nil && [inNotification object] != [self textView])\n\t\treturn;\n', ''),
    'keeps-fullwidth-background': (SYNTAX, '   else\n      TSRemoveFullwidthBackground(layoutManager, colorRange);\n', ''),
    'no-fullwidth-mark': (SYNTAX,
        '    TSMarkFullwidthBackground(layoutManager, colorRange, [self.syntaxColorScheme attributesForRole:TSSyntaxRoleFullwidthSymbol][NSBackgroundColorAttributeName]);\n', ''),
    'no-restore': (SYNTAX, '    [self restoreBraceHighlightsIn:aTextView range:colorRange];\n', ''),
    'contents-reset-without-coloring': (DOCUMENT,
        '\t\t[self colorizeVisibleAreaInTextView:textView1];\n\t\t[self colorizeVisibleAreaInTextView:textView2];\n\t}else{', '\t}else{'),
    'experiment-contents-reset-without-coloring': (EXPERIMENT,
        '                                        forCharacterRange:NSMakeRange(0, scrapTextView.string.length)];\n    [self colorizeExperimentSource];\n}',
        '                                        forCharacterRange:NSMakeRange(0, scrapTextView.string.length)];\n}'),
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

// The flash and background colors of the theme, light or dark as the window is.
static NSColor *FlashColor, *ThemeBackground, *DarkFlashColor, *DarkBackground;
@interface TSColorSupport : NSObject
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { return [self new]; }
- (NSColor *)colorFromDictionary:(NSDictionary *)dictionary andKey:(NSString *)key
{
    BOOL dark = dictionary == darkColors;
    if ([key isEqual:@"EditorFlash"]) return dark ? DarkFlashColor : FlashColor;
    if ([key isEqual:@"EditorBackground"]) return dark ? DarkBackground : ThemeBackground;
    return nil;
}
- (NSColor *)darkColorWithKey:(NSString *)key { return DarkFlashColor; }
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
// -[TSTextView fixupTabs] gives its style to the other half of the source of its document; here it has none.
@interface NSObject (TestSourceDocument)
- (NSTextView *)textView1;
- (NSTextView *)textView2;
@end
@interface TestSourceView : NSTextView
@property (weak) id document;
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
    NSArray *highlightedBraceLocations, *scrapHighlightedBraceLocations;
    NSRange highlightedContentRange, scrapHighlightedContentRange;
    NSUInteger braceHighlightGeneration, braceFlashGeneration, scrapBraceHighlightGeneration, scrapBraceFlashGeneration;
    NSUInteger highlightedTextLength, highlightedGeneration, scrapHighlightedTextLength, scrapHighlightedGeneration;
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
- (void)setupTagsAndLabelsAfterLoading;
- (void)setupTags;
- (void)colorizeAll;
- (void)colorizeVisibleAreaInTextView:(NSTextView *)aTextView;
- (void)fixColor:(NSUInteger)from :(NSUInteger)to;
- (BOOL)coloringWaitsForMarkedTextIn:(NSTextView *)aTextView;
- (void)colorAfterMarkedTextEnds;
- (BOOL)braceHighlightFits:(NSRange)range inTextView:(NSTextView *)aTextView;
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
- (void)setupTagsAndLabelsAfterLoading {}
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
    DarkFlashColor = NSColor.brownColor; DarkBackground = NSColor.blackColor;
    liteColors = @{@"name": @"lite"}; darkColors = @{@"name": @"dark"};
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


    // The Experiment source, shown.
    TestWindow *experiment = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 160) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    experiment.releasedWhenClosed = NO; experiment.shown = YES;
    ScrapTextView *scrap = [[ScrapTextView alloc] initWithFrame:NSMakeRect(0, 0, 420, 160)];
    InstallTextView(scrap, MakeScrollView(experiment));
    scrap.document = doc; scrap.richText = NO;
    [experiment makeFirstResponder:scrap];
    doc->scrapTextView = scrap;
    [doc observeExperimentSource];
    source.allowsUndo = YES;

    NSColor *contentColor = NSColor.cyanColor;
    [SUD setBool:YES forKey:CheckBraceEnabledKey];
    NSArray<NSTextView *> *sources = @[source, lower];

    for (NSTextView *view in @[source, scrap]) {
        BOOL inExperiment = view == scrap;
        NSArray<NSTextView *> *views = inExperiment ? @[scrap] : sources;
        #define EACH(condition) ({ BOOL all = YES; for (NSTextView *v in views) if (!(condition)) all = NO; all; })
        #define NAME(text) (inExperiment ? "Experiment: " text : "source: " text)
        #define LIT(i) EACH([Foreground(v, (i)) isEqual:braceColor])
        #define UNLIT(i) EACH(![Foreground(v, (i)) isEqual:braceColor])
        #define BRACES (inExperiment ? doc->scrapBraceHighlighting : doc->braceHighlighting)
        #define CONTENTS (inExperiment ? doc->scrapContentHighlighting : doc->contentHighlighting)
        void (^Show)(NSString *) = ^(NSString *text) {
            view.string = text;
            if (inExperiment) { [doc syncExperimentSourceDisplay]; [doc colorizeExperimentSource]; } else [doc colorizeAll];
            [view setSelectedRange:NSMakeRange(text.length, 0)];
            Spin(0.45);
        };
        // Moves the insertion point to before, then by one to after.
        void (^Pass)(NSUInteger, NSUInteger) = ^(NSUInteger before, NSUInteger after) {
            [view setSelectedRange:NSMakeRange(before, 0)];
            Spin(0.01);
            [view setSelectedRange:NSMakeRange(after, 0)];
        };
        void (^Recolor)(void) = ^{
            if (inExperiment) [doc colorizeExperimentSource]; else [doc colorizeAll];
        };

        // 1. Flash: a pair highlighted after another keeps its own time.
        [SUD setBool:NO forKey:AlwaysHighlightEnabledKey]; [SUD setBool:NO forKey:HighlightContentEnabledKey];
        Show(@"abc\n{}{}\nxyz\n");
        Pass(5, 6); Spin(0.02);
        Check(LIT(4) && LIT(5), NAME("moving past a brace highlights the pair"));
        Spin(0.23);
        Pass(6, 7); Spin(0.09);
        Check(LIT(6) && LIT(7) && BRACES, NAME("the earlier pair's reset does not end the newer pair's highlight"));
        Check(UNLIT(4) && UNLIT(5), NAME("the earlier pair is no longer highlighted"));
        Spin(0.30);
        Check(UNLIT(6) && UNLIT(7) && !BRACES, NAME("the newer pair goes out after its own time"));
        if (!inExperiment) {
            // Editing in the lower half: the upper half's report of its selection resets nothing.
            [lowerWindow makeFirstResponder:lower];
            doc.textView = lower;
            [lower setSelectedRange:NSMakeRange(5, 0)]; Spin(0.01);
            [lower setSelectedRange:NSMakeRange(6, 0)]; Spin(0.02);
            Check(LIT(4) && LIT(5), "lower half: moving past a brace highlights the pair in both halves");
            Spin(0.23);
            [lower setSelectedRange:NSMakeRange(7, 0)]; Spin(0.09);
            Check(LIT(6) && LIT(7), "lower half: the earlier pair's reset does not end the newer pair's highlight");
            Spin(0.40);
            [source setSelectedRange:NSMakeRange(source.string.length, 0)];
            [SUD setBool:YES forKey:AlwaysHighlightEnabledKey];
            [lower setSelectedRange:NSMakeRange(5, 0)]; Spin(0.02);
            [lower insertText:@"{" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.05);
            Check(LIT(5) && LIT(6), "lower half, Always: a typed brace stays highlighted though the upper half reports its selection");
            [SUD setBool:NO forKey:AlwaysHighlightEnabledKey];
            Spin(0.05);
            [mainWindow makeFirstResponder:source];
            doc.textView = source;
            Show(@"abc\n{}{}\nxyz\n");
        }

        // Typed braces, one after the other, and Undo.
        Show(@"x}}y");
        [view setSelectedRange:NSMakeRange(1, 0)]; Spin(0.01);
        [view insertText:@"{" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.25);
        [view insertText:@"{" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.09);
        Check(LIT(2) && LIT(3), NAME("a brace typed soon after another stays highlighted for its own time"));
        Spin(0.30);
        Check(UNLIT(1) && UNLIT(2) && UNLIT(3) && UNLIT(4) && !BRACES, NAME("typed braces go out"));
        if (!inExperiment) {
            [view.undoManager undo]; Spin(0.40);
            Check(view.string.length < 6 && UNLIT(1) && UNLIT(2) && UNLIT(3) && !BRACES, NAME("undoing typed braces leaves no highlight"));
        }

        // The flash of the background for an unmatched brace keeps its own time too, in light and dark windows.
        [SUD setBool:YES forKey:FlashBackgroundEnabledKey];
        for (int dark = 0; dark < 2; dark++) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            for (NSTextView *v in @[source, lower, scrap]) v.appearance = appearance;
            NSColor *flash = dark ? DarkFlashColor : FlashColor, *background = dark ? DarkBackground : ThemeBackground;
            if (inExperiment) background = ThemeBackground;  // -[ScrapTextView updateExperimentColors:]
            Show(@"abc\nx}}y\nxyz\n");
            view.backgroundColor = background;
            Pass(5, 6); Spin(0.02);
            Check([view.backgroundColor isEqual:flash], NAME("an unmatched brace flashes the background"));
            Spin(0.13);
            Pass(6, 7); Spin(0.10);
            Check([view.backgroundColor isEqual:flash], NAME("an earlier flash's reset does not end a newer flash"));
            Spin(0.20);
            Check([view.backgroundColor isEqual:background], NAME("the background comes back after the newer flash"));
        }
        for (NSTextView *v in @[source, lower, scrap]) v.appearance = nil;
        [SUD setBool:NO forKey:FlashBackgroundEnabledKey];

        // 2. A brace being composed is not highlighted; committed, it is.
        for (int always = 0; always < 2; always++) {
            [SUD setBool:always forKey:AlwaysHighlightEnabledKey];
            for (int commit = 0; commit < 2; commit++) {
                Show(@"abc\nx}\nxyz\n");
                Pass(4, 5); Spin(0.40);
                Compose(view, @[@"{"]); Spin(0.05);
                Check(view.hasMarkedText && UNLIT(5) && UNLIT(6) && !BRACES, NAME("a brace being composed is not highlighted"));
                Spin(0.30);
                Check(UNLIT(5) && UNLIT(6), NAME("nor later while it is composed"));
                if (commit) {
                    [view insertText:@"{" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.05);
                    Check(LIT(5) && LIT(6), NAME("the committed brace is highlighted as a typed one"));
                    Spin(0.35);
                    Check(always ? (LIT(5) && LIT(6)) : (UNLIT(5) && UNLIT(6)), NAME("the committed brace goes out as a typed one"));
                } else {
                    [view setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
                    [view unmarkText]; Spin(0.40);
                    Check(UNLIT(5) && !BRACES, NAME("no brace is highlighted after the composed brace is removed"));
                }
            }
        }

        // A reset that comes due while text is composed is done once it is committed or removed,
        // and the highlight goes as well when the text is committed or removed before then.
        for (int always = 0; always < 2; always++) {
            [SUD setBool:always forKey:AlwaysHighlightEnabledKey];
            for (int step = 0; step < 4; step++) {
                BOOL commit = step % 2, late = step / 2;
                Show(@"abc\nx}\nxyz\n");
                Pass(4, 5); Spin(0.40);
                [view insertText:@"{" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.03);
                Check(LIT(5) && LIT(6), NAME("a typed brace is highlighted"));
                Compose(view, @[@"\uff11", @"\uff11\uff12"]); Spin(late ? 0.36 : 0.06);
                if (commit) [view insertText:@"\uff11\uff12" replacementRange:NSMakeRange(NSNotFound, 0)];
                else { [view setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)]; [view unmarkText]; }
                NSUInteger close = [view.string rangeOfString:@"}"].location;
                // Colored again before the reset that the commit schedules: the highlight is not given again.
                Recolor();
                Check(UNLIT(5) && UNLIT(close), NAME("coloring right after the composed text ends does not give the expired highlight again"));
                Spin(0.05);
                Check(UNLIT(5) && UNLIT(close) && !BRACES, NAME("the highlight goes once the composed text is committed or removed"));
                Recolor();
                if (!inExperiment) [doc viewFrameDidChange:[NSNotification notificationWithName:NSViewFrameDidChangeNotification object:view]];
                Spin(0.40);
                Check(UNLIT(5) && UNLIT(close), NAME("and it is not given again when the text is colored again"));
                if (commit)
                    Check(EACH([Foreground(v, 6) isEqual:fullwidthColor] && [Background(v, 6) isEqual:fullwidthBackground]),
                          NAME("the committed fullwidth digits are colored"));
            }
        }
        [SUD setBool:NO forKey:AlwaysHighlightEnabledKey];

        // 3. Joined to a comment, fullwidth digits lose their background.
        for (int always = 0; always < 2; always++) {
            [SUD setBool:always forKey:AlwaysHighlightEnabledKey];
            Show(@"%x\n\uff11\uff12\nabc\n");
            Check(EACH([Background(v, 3) isEqual:fullwidthBackground]), NAME("fullwidth digits have their background"));
            [view setSelectedRange:NSMakeRange(3, 0)];
            [view deleteBackward:nil];
            if (inExperiment) [doc colorizeExperimentSource]; else [doc fixColor:0 :view.string.length];
            Spin(0.05);
            Check(EACH([Foreground(v, 2) isEqual:commentColor] && Background(v, 2) == nil && Background(v, 3) == nil),
                  NAME("fullwidth digits joined to a comment have no background"));
            [view insertText:@"\n" replacementRange:NSMakeRange(NSNotFound, 0)];
            if (inExperiment) [doc colorizeExperimentSource]; else [doc fixColor:0 :view.string.length];
            Spin(0.05);
            Check(EACH([Background(v, 3) isEqual:fullwidthBackground]), NAME("split off again, they have it again"));
        }

        // 4. Coloring again keeps the highlight of the braces and of their contents.
        [SUD setBool:YES forKey:HighlightContentEnabledKey];
        for (int always = 0; always < 2; always++) {
            [SUD setBool:always forKey:AlwaysHighlightEnabledKey];
            Show(@"abc\nx{a\uff11b}z\uff12\nxyz\n");
            Pass(5, 6); Spin(0.05);
            BOOL lit = always ? (LIT(5) && LIT(9)) : YES;
            Check(lit && EACH([Background(v, 6) isEqual:contentColor] && [Background(v, 7) isEqual:contentColor]
                              && [Background(v, 11) isEqual:fullwidthBackground]), NAME("the contents of the braces are highlighted"));
            NSArray *triggers = inExperiment ? @[@"resize", @"scroll", @"recolor"] : @[@"resize", @"scroll", @"lower half resize", @"recolor", @"settings"];
            for (NSString *trigger in triggers) {
                if ([trigger isEqual:@"resize"]) [doc viewFrameDidChange:[NSNotification notificationWithName:NSViewFrameDidChangeNotification object:view]];
                else if ([trigger isEqual:@"scroll"]) [doc viewBoundsDidChange:[NSNotification notificationWithName:NSViewBoundsDidChangeNotification object:view.enclosingScrollView.contentView]];
                else if ([trigger isEqual:@"lower half resize"]) [doc viewFrameDidChange:[NSNotification notificationWithName:NSViewFrameDidChangeNotification object:lower]];
                else if ([trigger isEqual:@"settings"]) [doc reColor:nil];
                else Recolor();
                Spin(0.02);
                BOOL braces = always ? (LIT(5) && LIT(9)) : YES;
                if (!(braces && EACH([Background(v, 6) isEqual:contentColor] && [Background(v, 7) isEqual:contentColor]
                                     && [Background(v, 11) isEqual:fullwidthBackground])))
                    printf("   after %s\n", trigger.UTF8String);
                Check(braces, NAME("coloring again keeps the brace highlight"));
                Check(EACH([Background(v, 6) isEqual:contentColor] && [Background(v, 7) isEqual:contentColor] && [Background(v, 11) isEqual:fullwidthBackground]),
                      NAME("coloring again keeps the contents highlighted, over a fullwidth digit too"));
            }
            // A new theme: its colors.
            NSDictionary *oldContent = highlightContentColorDict, *oldFullwidth = doc.fullwidthSymbolColorAttribute, *oldBraces = highlightBracesColorDict;
            highlightContentColorDict = @{NSBackgroundColorAttributeName: NSColor.greenColor};
            highlightBracesColorDict = @{NSForegroundColorAttributeName: NSColor.systemPinkColor};
            doc.fullwidthSymbolColorAttribute = @{NSForegroundColorAttributeName: fullwidthColor, NSBackgroundColorAttributeName: NSColor.lightGrayColor};
            Recolor(); Spin(0.02);
            Check(EACH([Background(v, 7) isEqual:NSColor.greenColor] && [Background(v, 6) isEqual:NSColor.greenColor] && [Background(v, 11) isEqual:NSColor.lightGrayColor]),
                  NAME("after a change of theme, the contents are highlighted in its color"));
            if (always) Check(EACH([Foreground(v, 5) isEqual:NSColor.systemPinkColor]), NAME("and the braces too"));
            highlightContentColorDict = oldContent; highlightBracesColorDict = oldBraces; doc.fullwidthSymbolColorAttribute = oldFullwidth;
            Recolor();
            Spin(0.40);

            // 5. When the highlight of the contents ends, fullwidth characters have their background again.
            [view setSelectedRange:NSMakeRange(0, 0)]; Spin(0.05);
            Check(!CONTENTS && EACH(Background(v, 6) == nil && [Background(v, 7) isEqual:fullwidthBackground] && [Background(v, 11) isEqual:fullwidthBackground]),
                  NAME("when the contents highlight ends, fullwidth characters have their background again"));
            Check(UNLIT(5) && UNLIT(9), NAME("and the braces are not highlighted"));
            Recolor(); Spin(0.02);
            Check(EACH(Background(v, 6) == nil && [Background(v, 7) isEqual:fullwidthBackground]), NAME("the ended highlight is not given again"));
        }
        // The active line keeps its color when the contents highlight ends.
        if (!inExperiment) {
            [SUD setBool:NO forKey:AlwaysHighlightEnabledKey];
            doc.syntaxcolorEntry = YES;
            Show(@"abc\nx{a}z\nxyz\n");
            Pass(5, 6); Spin(0.05);
            [view setSelectedRange:NSMakeRange(1, 0)]; [doc cursorMoved:view]; Spin(0.05);
            Check([Background(view, 0) isEqual:entryColor] && Background(view, 6) == nil, NAME("the active line is colored after the contents highlight ends"));
            doc.syntaxcolorEntry = NO;
            [doc removeCurrentLineColor:source]; [doc removeCurrentLineColor:lower];
        }
        [SUD setBool:NO forKey:HighlightContentEnabledKey];
        [SUD setBool:NO forKey:AlwaysHighlightEnabledKey];
        if (!inExperiment) [mainWindow makeFirstResponder:source];
    }

    if (failures) return 1;
    printf("PASS: brace highlights and backgrounds go away when they should, and only then, in both halves of the source "
           "and in the Experiment source\n");
} return 0; }
'''
replacements = {
    'DEFINES': defines, 'SCRAP_OVERRIDES': scrap_overrides, 'TAB_STOPS': tab_stops, 'BRACE_SEARCH': brace_search,
    'DOCUMENT_METHODS': document_methods, 'TOGGLE_XML': toggle_xml, 'TEXT_VIEW_TABS': text_view_tabs, 'SYNTAX': strip_imports(text[SYNTAX]), 'EXPERIMENT': strip_imports(text[EXPERIMENT]),
    'TRY_SCRAP_SYNCS': 'YES' if '[self syncExperimentSourceDisplay];' in try_scrap else 'NO',
}
for name, value in replacements.items():
    program = program.replace(f'@@{name}@@', value)

with tempfile.TemporaryDirectory(prefix='texshop-brace-highlight-states-') as tmp:
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
