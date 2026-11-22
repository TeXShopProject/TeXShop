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
- Text composed in the same keystroke as a typed brace is not highlighted in its
  place, and a closing brace being composed shows no indicator at its partner.
- The highlight ends when its braces change without the insertion point moving,
  when matching or the highlight of contents is turned off, and when typing moves
  to the other half of a split window.
- A change of theme or of one of its colors (each step of a dragged color well)
  keeps the highlights, in the new colors, in light and dark windows.
- With Highlight Current Line and the block cursor, fullwidth backgrounds and
  highlighted contents still show, on the active line and on the others.
- Removing the color of the active line (Highlight Current Line turned off, the
  window split, the Experiment source after composed text that coloring waited for)
  leaves fullwidth backgrounds and highlighted contents.
- With Highlight Fullwidth Letters and Symbols off (on in the factory defaults),
  fullwidth letters, digits and symbols are colored exactly as other text, by every
  kind of coloring again (typing, pasting, Undo, resizing, scrolling, a change of
  settings or theme, commenting out, the active line, highlighted contents, the flash),
  also when the switch changes while text is composed and on lines out of sight; on
  again, they have the theme's colors again. Syntax coloring of the document turned
  off removes the fullwidth colors too, whichever is turned off first; turned on
  again, the switch decides.

All this in either half of a split window and in the Experiment source, with "Flash"
and "Always" highlighting. The production categories TSDocument (SyntaxHighlighting) and
TSDocument (ExperimentSource), and TSDocument (Color) for changes of theme colors, are
compiled unchanged onto a small TSDocument stand-in, with the production TSDocument
methods for brace matching, its text view delegate method, the overrides of
ScrapTextView and the real TSLayoutManager. Text is composed through the
NSTextInputClient methods that input methods call. Windows are never ordered on
screen. Preferences stay in memory."""
from pathlib import Path
import argparse, plistlib, re, subprocess, sys, tempfile
from source_tree import include_args, source_file

SYNTAX = 'Sources/Editor/TSDocument-Syntax.m'
EXPERIMENT = 'Sources/Editor/TSDocument-ExperimentSource.m'
COLOR = 'Sources/Editor/TSDocument-Color.m'
DOCUMENT = 'Sources/Document/TSDocument.m'
SCRAP_VIEW = 'Sources/Editor/ScrapTextView.m'
SCRAP = 'Sources/Document/TSDocument-Scrap.m'
XML = 'Sources/Document/TSDocument-XML.m'
TEXT_VIEW = 'Sources/Editor/TSTextView.m'
EFFECTS = 'Sources/Settings/TSPreferenceEffects.h'
FACTORY = 'Resources/Defaults/FactoryDefaults.plist'

MUTATIONS = {
    'highlights-moved-braces': (DOCUMENT,
        '\tif (![self braceHighlightFits:NSMakeRange(MIN(location1, location2), ABS(location1 - location2) + 1) inTextView:textView1])\n\t\treturn;\n', ''),
    'highlights-moved-contents': (DOCUMENT,
        '\tif (![self braceHighlightFits:NSRangeFromString(range) inTextView:textView1])\n\t\treturn;\n', ''),
    'experiment-highlights-moved-braces': (EXPERIMENT,
        '    if (![self braceHighlightFits:NSMakeRange(MIN(location1, location2), ABS(location1 - location2) + 1) inTextView:scrapTextView])\n        return;\n', ''),
    'indicator-while-composing': (DOCUMENT, '\tif ([textView1 hasMarkedText] || [textView2 hasMarkedText])\n\t\treturn;\n', ''),
    'experiment-indicator-while-composing': (EXPERIMENT, '    if (scrapTextView.hasMarkedText)\n        return;\n', ''),
    'restores-unmatched': (SYNTAX,
        '    if ([[aTextView string] length] != (experiment ? scrapHighlightedTextLength : highlightedTextLength) ||\n        ![self braceHighlightFits:pair inTextView:aTextView]) {',
        '    if (NO) {'),
    'restores-turned-off-kinds': (SYNTAX, "(open == '{' && close == '}' && [SUD boolForKey:CheckBraceEnabledKey])", "(open == '{' && close == '}')"),
    'no-reset-when-matching-off': (DOCUMENT,
        '\t\tif (highlightingContent)\n\t\t\t[self performSelector:resetBackgroundSelector withObject:nil afterDelay:0];\n\t\tif (highlightingBraces)\n\t\t\t[self performSelector:resetHighlightSelector withObject:nil afterDelay:0];\n\t\treturn;',
        '\t\treturn;'),
    'no-resync-on-other-half': (DOCUMENT, '\tif (otherHalf) {', '\tif (NO) {'),
    'active-line-wipes-fullwidth': (SYNTAX, '            TSRestoreFullwidthBackground(layoutManager, TSVisibleCharacterRange(aTextView));\n', ''),
    'active-line-wipes-contents': (SYNTAX, '            [self restoreBraceHighlightsIn:aTextView range:TSVisibleCharacterRange(aTextView)];\n', ''),
    'stale-fullwidth-marks': (SYNTAX, '      [layoutManager removeTemporaryAttribute:TSFullwidthBackgroundMark forCharacterRange:colorRange];\n', ''),
    'flash-ends-with-theme-background': (DOCUMENT,
        'opaqueColorForKey: @"EditorBackground" fromDictionary: colorDictionary isWindowDark: withDarkColors]',
        'colorFromDictionary: colorDictionary andKey: @"EditorBackground"]'),
    'flash-ends-in-light-theme': (DOCUMENT,
        'fromDictionary: colorDictionary isWindowDark: withDarkColors]', 'fromDictionary: liteColors isWindowDark: NO]'),
    'no-highlight-generation': (DOCUMENT,
        '    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != braceHighlightGeneration)\n        return;\n', ''),
    'no-flash-generation': (DOCUMENT,
        '    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != braceFlashGeneration)\n        return;\n', ''),
    'no-experiment-highlight-generation': (EXPERIMENT,
        '- (void)resetExperimentHighlight:(id)sender\n{\n    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != scrapBraceHighlightGeneration)\n        return;\n',
        '- (void)resetExperimentHighlight:(id)sender\n{\n'),
    'no-experiment-flash-generation': (EXPERIMENT,
        '    if ([sender isKindOfClass:[NSNumber class]] && [sender unsignedIntegerValue] != scrapBraceFlashGeneration)\n        return;\n', ''),
    'highlights-composed-brace': (DOCUMENT, '    if ([selectionView hasMarkedText]) {', '    if (NO) {'),
    'keeps-braces-while-composing': (DOCUMENT,
        '    if ([self coloringWaitsForMarkedTextIn:textView]) {\n        highlightedBraceLocations = nil;\n', '    if ([self coloringWaitsForMarkedTextIn:textView]) {\n'),
    'keeps-experiment-braces-while-composing': (EXPERIMENT,
        '    if ([self coloringWaitsForMarkedTextIn:scrapTextView]) {\n        scrapHighlightedBraceLocations = nil;\n', '    if ([self coloringWaitsForMarkedTextIn:scrapTextView]) {\n'),
    'other-half-resets': (DOCUMENT,
        '\tif ([inNotification object] != nil && [inNotification object] != [self textView])\n\t\treturn;\n', ''),
    'keeps-fullwidth-background': (SYNTAX, '   } else\n      TSRemoveFullwidthBackground(layoutManager, colorRange);\n', '   }\n'),
    'keeps-contents-turned-off': (SYNTAX, '    if (highlightsContents && ![SUD boolForKey:HighlightContentEnabledKey]) {', '    if (NO) {'),
    'no-fullwidth-mark': (SYNTAX,
        '    TSMarkFullwidthBackground(layoutManager, colorRange, [self.syntaxColorScheme attributesForRole:TSSyntaxRoleFullwidthSymbol][NSBackgroundColorAttributeName]);\n', ''),
    'no-restore': (SYNTAX, '    [self restoreBraceHighlightsIn:aTextView range:colorRange];\n', ''),
    'contents-reset-without-coloring': (DOCUMENT,
        '\t\t[self colorizeVisibleAreaInTextView:textView1];\n\t\t[self colorizeVisibleAreaInTextView:textView2];\n\t}else{', '\t}else{'),
    'experiment-contents-reset-without-coloring': (EXPERIMENT,
        '                                        forCharacterRange:NSMakeRange(0, scrapTextView.string.length)];\n    [self colorizeExperimentSource];\n}',
        '                                        forCharacterRange:NSMakeRange(0, scrapTextView.string.length)];\n}'),
    'line-removal-wipes-fullwidth': (SYNTAX,
        '    TSRestoreFullwidthBackground(layoutManager, TSVisibleCharacterRange(aTextView));\n    [self restoreBraceHighlightsIn:aTextView range:TSVisibleCharacterRange(aTextView)];\n}', '}'),
    # Highlight Fullwidth Letters and Symbols.
    'syntax-off-keeps-fullwidth': (SYNTAX, '\t\tTSRemoveFullwidthBackground([textView1 layoutManager], theRange);\n\t\tTSRemoveFullwidthBackground([textView2 layoutManager], theRange);\n\t\tTSRemoveFullwidthBackground([scrapTextView layoutManager], NSMakeRange(0, scrapTextView.string.length));\n', ''),
    'syntax-off-loses-active-line': (SYNTAX, '\t\tif (self.syntaxcolorEntry) {\n\t\t\t[self cursorMoved:textView1];', '\t\tif (NO) {\n\t\t\t[self cursorMoved:textView1];'),
    'brace-reset-loses-active-line': (DOCUMENT, '\tif (self.syntaxcolorEntry && (!fileIsTex || !self.syntaxColor)) {', '\tif (NO) {'),
    'experiment-brace-reset-loses-active-line': (EXPERIMENT, '    if (self.syntaxcolorEntry && (!fileIsTex || !self.syntaxColor))\n        [self refreshExperimentCurrentLine];', ''),
    'fullwidth-switch-ignored': (SYNTAX, '[SUD boolForKey:HighlightFullwidthSymbolsKey] &&\n        [self.syntaxColorScheme', '[self.syntaxColorScheme'),
    'fullwidth-not-posted': (EFFECTS, 'CheckParenEnabledKey, HighlightFullwidthSymbolsKey, ', 'CheckParenEnabledKey, '),
    'fullwidth-not-observed': (DOCUMENT, 'addObserver:self selector:@selector(colorizeAll)', 'addObserver:self selector:@selector(description)'),
    'fullwidth-off-by-default': (FACTORY, '<key>HighlightFullwidthSymbols</key>\n\t<string>YES</string>', '<key>HighlightFullwidthSymbols</key>\n\t<string>NO</string>'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = {path: (root / path).read_text(encoding='latin1') for path in (SYNTAX, EXPERIMENT, COLOR, DOCUMENT, SCRAP_VIEW, SCRAP, XML, TEXT_VIEW, EFFECTS, FACTORY)}
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
    '- (IBAction)toggleSyntaxColor:sender {', '- (IBAction)toggleSyntaxColorEntry:sender {', '- (IBAction)toggleBlockCursor:sender {',
    '- (void) applyInvisibleCharactersShowing', '- (void) showHideInvisibleCharacters: sender',
    '- (void) showHideLineNumbers: sender', '- (void)setDocumentFontFromPreferences:(NSNotification *)notification',
    '- (void)fixUpTabs {', '- (void)setLineBreakMode:(id)sender', '- (IBAction)toggleIndexColor:sender {',
    '- (BOOL)indexColorState',
    '- (void)resetHighlight:(id)sender', '- (void)showIndicator:(NSString*)range', '- (void)resetBackgroundColor:(id)sender',
    '- (void)resetBackgroundColorOfTextView:(id)sender', '- (void)highlightContent:(NSString*)range',
    '- (void)highlightBracesAt:(NSArray*)locations',
    '- (void)textViewDidChangeSelection:(NSNotification *)inNotification',
    '- (void)matchBracesForSelectionInTextView:(NSTextView *)aTextView',
    '- (void)flashMatchForCharacter:(NSString *)replacementString range:(NSRange)affectedCharRange inTextView:(NSTextView *)aTextView',
    '- (BOOL)textView:(NSTextView *)aTextView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString',
    '- (void) setTextView: (id)aView',
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
# Settings posts this after each change of the theme or of one of its colors, as the document observes it.
assert 'NSString *SourceColorChangedNotification = @"SourceColorChangedNotification";' in globals_m
assert 'selector:@selector(changeColorsFromNotification:)\n          name:SourceColorChangedNotification object:nil];' in text[DOCUMENT]
keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
# Highlight Fullwidth Letters and Symbols: its factory default, which TSAppDelegate registers; whether Settings posts
# the notification for a recoloring when it changes; whether the document colors its views again then.
factory_fullwidth = plistlib.loads(text[FACTORY].encode('latin1'))['HighlightFullwidthSymbols']
assert isinstance(factory_fullwidth, str)
recolor_keys = re.search(r'TSPreferenceNeedsRecolorNotification: @\[([^\]]*)\]', text[EFFECTS]).group(1)
fullwidth_recolors = 'HighlightFullwidthSymbolsKey' in re.findall(r'\w+', recolor_keys)
observes_recolor = re.search(r'addObserver:self selector:@selector\(colorizeAll\)\s*name:@"NeedsForRecolorNotification" object:nil\]', text[DOCUMENT]) is not None
defines = '\n'.join(f'#define {k} {v}' for k, v in sorted(keys.items()))
marker_keys = '\n'.join(f'NSString *{k} = {keys[k]};' for k in [
    'showSpaceCharacterKey', 'showFullwidthSpaceCharacterKey', 'showTabCharacterKey', 'showNewLineCharacterKey',
    'SpaceCharacterKindKey', 'FullwidthSpaceCharacterKindKey', 'TabCharacterKindKey', 'NewLineCharacterKindKey', 'LineNumberSizeKey'])

program = r'''
#import <Cocoa/Cocoa.h>
#import "TSThemeSystemColor.h"
#import "TSFontSupport.h"
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
static NSColor *FlashColor, *ThemeBackground, *DarkFlashColor, *DarkBackground, *BuiltInBackground, *BuiltInDarkBackground;
@interface TSColorSupport : NSObject
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { return [self new]; }
- (NSColor *)colorFromDictionary:(NSDictionary *)dictionary andKey:(NSString *)key
{
    NSArray *components = [dictionary[key] isKindOfClass:[NSArray class]] ? dictionary[key] : nil;
    if (components)
        return [NSColor colorWithSRGBRed:[components[0] doubleValue] green:[components[1] doubleValue] blue:[components[2] doubleValue]
                                   alpha:components.count > 3 ? [components[3] doubleValue] : 1];
    if (dictionary[@"theme"]) return nil;
    BOOL dark = dictionary == darkColors;
    if ([key isEqual:@"EditorFlash"]) return dark ? DarkFlashColor : FlashColor;
    if ([key isEqual:@"EditorBackground"]) return dark ? DarkBackground : ThemeBackground;
    return nil;
}
- (NSColor *)colorAndAlphaFromDictionary:(NSDictionary *)dictionary andKey:(NSString *)key { return [self colorFromDictionary:dictionary andKey:key]; }
- (NSColor *)liteColorAndAlphaWithKey:(NSString *)key { return nil; }
- (NSColor *)darkColorAndAlphaWithKey:(NSString *)key { return nil; }
// The built-in colors of a mode, for a theme that lacks one.
- (NSColor *)darkColorWithKey:(NSString *)key { return [key isEqual:@"EditorBackground"] ? BuiltInDarkBackground : DarkFlashColor; }
- (NSColor *)liteColorWithKey:(NSString *)key { return [key isEqual:@"EditorBackground"] ? BuiltInBackground : FlashColor; }
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)dictionary isWindowDark:(BOOL)dark
{
    return [self colorFromDictionary:dictionary andKey:key] ?: (dark ? [self darkColorWithKey:key] : [self liteColorWithKey:key]);
}
// The cursor and the selection, as TSColorSupport gives them.
- (NSColor *)insertionPointColorFromDictionary:(NSDictionary *)dictionary isWindowDark:(BOOL)dark
{
    return TSThemeUsesSystemColor(dictionary, TSThemeInsertionPointUsesSystemColorKey) ? NSColor.textInsertionPointColor : [self opaqueColorForKey:@"EditorInsertionPoint" fromDictionary:dictionary isWindowDark:dark];
}
- (NSColor *)selectionColorFromDictionary:(NSDictionary *)dictionary isWindowDark:(BOOL)dark
{
    return TSThemeUsesSystemColor(dictionary, TSThemeSelectionUsesSystemColorKey) ? NSColor.selectedTextBackgroundColor : [self opaqueColorForKey:TSThemeSelectionKey fromDictionary:dictionary isWindowDark:dark];
}
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

@interface NSObject (TestStatusBar)
- (void)selectionDidChange;
- (void)updatePreviewPaperColor;
@end
// What -changeColorsUsingDictionary: sets besides the source.
NSColor *ReverseSyncColor, *ImageForegroundColor, *ImageBackgroundColor, *PreviewDirectSyncColor;
extern NSColor *InvisibleColor;
#import "TSThemeAlpha.h"
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
    NSWindow *textWindow, *fullSplitWindow, *outputWindow;
    NSTextView *outputText;
}
@property (strong) NSDictionary *EntryColorAttribute, *commandColorAttribute, *commentColorAttribute,
    *explColorAttribute1, *explColorAttribute2, *explColorAttribute3, *explColorAttribute4, *explColorAttribute5,
    *explColorAttribute6, *explColorAttribute7, *footnoteColorAttribute, *fullwidthSymbolColorAttribute,
    *indexColorAttribute, *markerColorAttribute, *markerColorCurlyAttribute, *markerColorParenAttribute,
    *markerColorSquareAttribute, *regularColorAttribute;
@property BOOL blockCursor, fileIsXML, syntaxColor, syntaxcolorEntry, useExplColor, coloringWaitsForMarkedText;
// The selection of the source and the view marked by a reverse sync (TSDocument).
@property (strong) NSColor *sourceSelectionColor;
@property (weak) NSTextView *reverseSyncTextView;
@property (getter=textSelectionYellow) BOOL textSelectionYellow;
@property (strong) TSSyntaxColorScheme *syntaxColorScheme;
@property (strong) NSTextStorage *textStorage;
@property (strong) NSTextView *textView;
@property (strong) NSScrollView *logScrollView;
@property (strong) NoodleLineNumberView *lineNumberView1, *lineNumberView2, *logLineNumberView;
@property (strong) id sourceStatusBar, myPDFKitView, myPDFKitView2;
@property (strong) NSTextView *logTextView;
@property (strong) NSWindow *logWindow, *pdfKitWindow;
@property (strong) NSDictionary *commentXMLColorAttribute, *tagXMLColorAttribute, *specialXMLColorAttribute, *parameterXMLColorAttribute, *valueXMLColorAttribute;
- (void)changeColorsFromNotification:(NSNotification *)notification;
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
- (IBAction)toggleIndexColor:(id)sender;
- (IBAction)toggleSyntaxColor:(id)sender;
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
// Made from the attributes that -changeColorsUsingDictionary: takes from the scheme it sets.
- (TSSyntaxColorScheme *)syntaxColorScheme { return SchemeOf(self); }
- (void)setSyntaxColorScheme:(TSSyntaxColorScheme *)scheme {}
- (void)setupTagsAndLabelsAfterLoading {}
- (void)setupTags {}
@@DOCUMENT_METHODS@@
@@TOGGLE_XML@@
@end

@@SYNTAX@@
@@EXPERIMENT@@
@@COLOR@@

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
    // The factory default of Highlight Fullwidth Letters and Symbols, as TSAppDelegate registers it.
    [SUD registerDefaults:@{HighlightFullwidthSymbolsKey: @"@@FULLWIDTH_FACTORY@@"}];
    [NSApplication sharedApplication];
    indicators = [NSMutableArray array]; flashSelections = [NSMutableArray array];
    FlashColor = NSColor.orangeColor; ThemeBackground = NSColor.whiteColor; XMLColor = NSColor.brownColor;
    DarkFlashColor = NSColor.brownColor; DarkBackground = NSColor.blackColor;
    BuiltInBackground = NSColor.lightGrayColor; BuiltInDarkBackground = NSColor.darkGrayColor;
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
    doc->textWindow = mainWindow;  // its appearance chooses the dark colors, as the source's does
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
    [NSNotificationCenter.defaultCenter addObserver:doc selector:@selector(changeColorsFromNotification:) name:@"SourceColorChangedNotification" object:nil];
    // As -[TSDocument windowControllerDidLoadNib:]: a change in Settings that needs a recoloring.
    if (@@OBSERVES_RECOLOR@@)
        [NSNotificationCenter.defaultCenter addObserver:doc selector:@selector(colorizeAll) name:@"NeedsForRecolorNotification" object:nil];

    NSColor *contentColor = NSColor.cyanColor;
    // What a change of theme replaces in the document, to be put back after a test of one.
    NSArray *themedKeys = @[@"EntryColorAttribute", @"commandColorAttribute", @"commentColorAttribute", @"explColorAttribute1", @"explColorAttribute2",
                            @"explColorAttribute3", @"explColorAttribute4", @"explColorAttribute5", @"explColorAttribute6", @"explColorAttribute7",
                            @"footnoteColorAttribute", @"fullwidthSymbolColorAttribute", @"indexColorAttribute", @"markerColorAttribute",
                            @"markerColorCurlyAttribute", @"markerColorParenAttribute", @"markerColorSquareAttribute", @"regularColorAttribute"];
    NSDictionary *(^SaveTheme)(void) = ^NSDictionary *{
        NSMutableDictionary *saved = [NSMutableDictionary dictionary];
        for (NSString *key in themedKeys) { id value = [doc valueForKey:key]; if (value) saved[key] = value; }
        if (highlightBracesColorDict) saved[@"braces"] = highlightBracesColorDict;
        if (highlightContentColorDict) saved[@"contents"] = highlightContentColorDict;
        saved[@"lite"] = liteColors; saved[@"dark"] = darkColors;
        return saved;
    };
    void (^RestoreTheme)(NSDictionary *) = ^(NSDictionary *saved) {
        for (NSString *key in themedKeys) [doc setValue:saved[key] forKey:key];
        highlightBracesColorDict = saved[@"braces"]; highlightContentColorDict = saved[@"contents"];
        liteColors = saved[@"lite"]; darkColors = saved[@"dark"];
    };
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
            // Typing moves to the other half, whose insertion point is elsewhere: the highlight
            // of the first half ends there and in the other half.
            [SUD setBool:YES forKey:AlwaysHighlightEnabledKey]; [SUD setBool:YES forKey:HighlightContentEnabledKey];
            Show(@"abc\nx{a\uff11b}z\nxyz plain\n");
            [lower setSelectedRange:NSMakeRange(16, 0)];
            Pass(5, 6); Spin(0.05);
            Check(LIT(5) && LIT(9) && EACH([Background(v, 6) isEqual:contentColor]), "split: braces are highlighted in the upper half");
            [lowerWindow makeFirstResponder:lower];
            doc.textView = lower;  // as -[TSTextEditorWindow makeFirstResponder:] does
            Spin(0.05);
            Check(UNLIT(5) && UNLIT(9) && EACH(Background(v, 6) == nil && [Background(v, 7) isEqual:fullwidthBackground]),
                  "split: when typing moves to the other half, the highlight of the first half ends");
            [lower setSelectedRange:NSMakeRange(9, 0)]; Spin(0.01);
            [lower setSelectedRange:NSMakeRange(10, 0)]; Spin(0.05);
            Check(LIT(5) && LIT(9), "split: braces next to the insertion point of the other half are highlighted");
            [mainWindow makeFirstResponder:source];
            doc.textView = source;
            Spin(0.05);
            Check(UNLIT(5) && UNLIT(9), "split: and back in the first half, that highlight ends as well");
            [SUD setBool:NO forKey:AlwaysHighlightEnabledKey]; [SUD setBool:NO forKey:HighlightContentEnabledKey];
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
            mainWindow.appearance = appearance;
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
        mainWindow.appearance = nil;
        // After the flash, the source has the background that Settings gave it, also with a theme
        // that has lost all its colors or only its background; a change of theme meanwhile stays.
        if (!inExperiment)
            for (int dark = 0; dark < 2; dark++)
                for (int kind = 0; kind < 3; kind++) {
                    NSDictionary *savedTheme = SaveTheme();
                    NSDictionary *theme = kind == 0 ? @{@"theme": @YES}
                        : @{@"theme": @YES, @"EditorFlash": @[@1, @0.5, @0], @"EditorText": @[@0.1, @0.1, @0.1], @"EditorHighlightContent": @[@0.2, @0.9, @0.9]};
                    if (dark) darkColors = theme; else liteColors = theme;
                    for (NSTextView *v in @[source, lower]) v.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                    mainWindow.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                    [NSNotificationCenter.defaultCenter postNotificationName:@"SourceColorChangedNotification" object:nil];
                    if (kind == 2)  // as Settings gives a color the theme lacks once missing colors are resolved there
                        for (NSTextView *v in @[source, lower]) v.backgroundColor = dark ? BuiltInDarkBackground : BuiltInBackground;
                    NSColor *settings = source.backgroundColor;
                    Show(@"abc\nx}}y\nxyz\n");
                    Pass(5, 6); Spin(0.02);
                    BOOL flashed = ![source.backgroundColor isEqual:settings];
                    Spin(0.28);
                    BOOL same = YES;
                    for (NSTextView *v in @[source, lower]) if (!(v.backgroundColor == settings || [v.backgroundColor isEqual:settings])) same = NO;
                    Check(flashed && same, kind == 0 ? (dark ? "source: dark theme without colors: after a flash, the background Settings gave" : "source: light theme without colors: after a flash, the background Settings gave")
                                     : kind == 1 ? (dark ? "source: dark theme without a background: after a flash, the background Settings gave" : "source: light theme without a background: after a flash, the background Settings gave")
                                     : (dark ? "source: dark, resolved background: after a flash, the background Settings gave" : "source: light, resolved background: after a flash, the background Settings gave"));
                    RestoreTheme(savedTheme);
                    for (NSTextView *v in @[source, lower]) { v.appearance = nil; v.backgroundColor = ThemeBackground; }
                    mainWindow.appearance = nil;
                    Recolor();
                }
        // A change of theme during a flash, with or without a second flash before the first
        // ends, and to a background of the flash's own color: the last theme's background stays.
        for (int dark = 0; dark < 2; dark++)
            for (int step = 0; step < 5; step++) {
                // 0 one flash, 1 a change, 2 a change to the flash's color, 3 a change and a second flash, 4 two flashes
                NSDictionary *savedTheme = SaveTheme();
                NSArray *flashRGB = @[@0.93, @0.42, @0.23];
                NSDictionary *first = @{@"theme": @YES, @"EditorFlash": flashRGB, @"EditorBackground": dark ? @[@0.1, @0.12, @0.16] : @[@0.94, @0.94, @0.92]};
                NSDictionary *second = @{@"theme": @YES, @"EditorFlash": flashRGB, @"EditorBackground": step == 2 ? flashRGB : @[@0.22, @0.59, @0.39]};
                NSAppearance *appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                NSArray<NSTextView *> *flashed = inExperiment ? @[scrap] : @[source, lower];
                for (NSTextView *v in flashed) v.appearance = appearance;
                mainWindow.appearance = appearance;
                if (dark) darkColors = first; else liteColors = first;
                ThemeBackground = [NSColor colorWithSRGBRed:[first[@"EditorBackground"][0] doubleValue] green:[first[@"EditorBackground"][1] doubleValue] blue:[first[@"EditorBackground"][2] doubleValue] alpha:1];
                [NSNotificationCenter.defaultCenter postNotificationName:@"SourceColorChangedNotification" object:nil];
                if (inExperiment) [scrap updateExperimentColors:nil];
                Show(@"abc\nx}}y\nxyz\n");
                Pass(5, 6); Spin(0.025);
                BOOL started = ![view.backgroundColor isEqual:ThemeBackground];
                NSColor *expected = ThemeBackground;
                if (step >= 1 && step <= 3) {
                    if (dark) darkColors = second; else liteColors = second;
                    ThemeBackground = [NSColor colorWithSRGBRed:[second[@"EditorBackground"][0] doubleValue] green:[second[@"EditorBackground"][1] doubleValue] blue:[second[@"EditorBackground"][2] doubleValue] alpha:1];
                    [NSNotificationCenter.defaultCenter postNotificationName:@"SourceColorChangedNotification" object:nil];
                    if (inExperiment) [scrap updateExperimentColors:nil];  // as ScrapTextView observes the change itself
                    expected = view.backgroundColor;
                    Spin(0.03);
                }
                if (step >= 3) { [view setSelectedRange:NSMakeRange(7, 0)]; Spin(0.02); }
                Spin(0.32);
                BOOL same = YES;
                for (NSTextView *v in flashed) if (!(v.backgroundColor == expected || [v.backgroundColor isEqual:expected])) same = NO;
                const char *names[] = {"one flash", "a change of theme during it", "a change to the flash's color", "a change and a second flash", "two flashes"};
                char name[200];
                snprintf(name, sizeof name, "%s %s, %s: the background of the last theme after the flash", inExperiment ? "Experiment:" : "source:", dark ? "dark" : "light", names[step]);
                Check(started && same, name);
                RestoreTheme(savedTheme);
                ThemeBackground = NSColor.whiteColor;
                for (NSTextView *v in flashed) { v.appearance = nil; v.backgroundColor = ThemeBackground; }
                mainWindow.appearance = nil;
                Recolor(); Spin(0.30);
            }
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
            // Highlight Current Line turned on afterwards does not give it back.
            doc.syntaxcolorEntry = YES;
            for (NSTextView *v in views) [doc cursorMoved:v];
            Check(EACH(![Background(v, 2) isEqual:fullwidthBackground] && ![Background(v, 3) isEqual:fullwidthBackground]),
                  NAME("nor once the active line is drawn"));
            doc.syntaxcolorEntry = NO;
            for (NSTextView *v in views) [doc removeCurrentLineColor:v];
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

        // 6. Text composed in the same keystroke as a brace: the positions matched before
        // are no longer those of the braces, and nothing is highlighted there.
        for (int always = 0; always < 2; always++) {
            [SUD setBool:always forKey:AlwaysHighlightEnabledKey];
            [SUD setBool:YES forKey:HighlightContentEnabledKey];
            for (int commit = 0; commit < 2; commit++) {
                Show(@"x}}y");
                [view setSelectedRange:NSMakeRange(1, 0)]; Spin(0.01);
                [view insertText:@"{" replacementRange:NSMakeRange(NSNotFound, 0)];
                Compose(view, @[@"\uff11"]); Spin(0.05);
                Check(view.hasMarkedText && EACH(![Foreground(v, 2) isEqual:braceColor] && ![Background(v, 2) isEqual:contentColor]),
                      NAME("text composed right after a typed brace is not highlighted"));
                Spin(0.40);
                Check(EACH(![Foreground(v, 2) isEqual:braceColor] && ![Background(v, 2) isEqual:contentColor]),
                      NAME("nor after the time of the highlight"));
                if (commit) [view insertText:@"\uff11" replacementRange:NSMakeRange(NSNotFound, 0)];
                else { [view setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)]; [view unmarkText]; }
                Spin(0.05); Recolor(); Spin(0.40);
                BOOL none = YES;
                for (NSUInteger i = 0; i < view.string.length; i++)
                    if (!EACH(![Foreground(v, i) isEqual:braceColor] && ![Background(v, i) isEqual:contentColor])) none = NO;
                Check(none, NAME("once it is committed or removed, no highlight is left anywhere"));
                if (commit) Check(EACH([Background(v, 2) isEqual:fullwidthBackground]), NAME("the committed digit has the fullwidth background"));
            }
        }
        [SUD setBool:NO forKey:HighlightContentEnabledKey];
        [SUD setBool:NO forKey:AlwaysHighlightEnabledKey];

        // 7. A closing brace being composed shows no indicator at its partner; committed, it does.
        [SUD setBool:YES forKey:ParensMatchingEnabledKey]; [SUD setBool:YES forKey:brieflyFlashYellowForMatchKey];
        for (int commit = 0; commit < 2; commit++) {
            Show(@"x{y");
            [view setSelectedRange:NSMakeRange(3, 0)]; Spin(0.40);
            [indicators removeAllObjects];
            Compose(view, @[@"}"]); Spin(0.06);
            Check(indicators.count == 0, NAME("a closing brace being composed shows no indicator at its partner"));
            if (commit) {
                [view insertText:@"}" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.06);
                Check([indicators containsObject:[NSString stringWithFormat:@"%@ {1, 1}", inExperiment ? @"experiment" : @"source"]],
                      NAME("a committed closing brace shows the indicator at its partner"));
            } else {
                [view setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)]; [view unmarkText]; Spin(0.06);
                Check(indicators.count == 0, NAME("nor once the composed brace is removed"));
            }
        }
        [indicators removeAllObjects];
        Show(@"x{y");
        [view setSelectedRange:NSMakeRange(3, 0)]; Spin(0.02);
        [view insertText:@"}" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.06);
        Check(indicators.count > 0, NAME("a typed closing brace shows the indicator as before"));
        [SUD setBool:NO forKey:ParensMatchingEnabledKey];

        // 8. Matching turned off, or the text changed where braces are highlighted: the highlight ends.
        [SUD setBool:YES forKey:AlwaysHighlightEnabledKey]; [SUD setBool:YES forKey:HighlightContentEnabledKey];
        NSArray *kinds = @[CheckBraceEnabledKey, CheckBracketEnabledKey, CheckSquareBracketEnabledKey, CheckParenEnabledKey];
        for (int which = 0; which < 2; which++) {
            Show(@"abc\nx{a\uff11b}z\uff12\nxyz\n");
            Pass(5, 6); Spin(0.05);
            Check(LIT(5) && LIT(9) && EACH([Background(v, 6) isEqual:contentColor]), NAME("braces are highlighted"));
            for (NSString *key in (which ? @[CheckBraceEnabledKey] : kinds)) [SUD setBool:NO forKey:key];
            Recolor(); Spin(0.05);
            Check(UNLIT(5) && UNLIT(9) && EACH(Background(v, 6) == nil), NAME("coloring right after matching is turned off ends the highlight"));
            [view setSelectedRange:NSMakeRange(1, 0)]; Spin(0.05);
            [view setSelectedRange:NSMakeRange(6, 0)]; Spin(0.50);
            Recolor(); Spin(0.05);
            Check(UNLIT(5) && UNLIT(9) && EACH(Background(v, 6) == nil && [Background(v, 7) isEqual:fullwidthBackground]),
                  which ? NAME("with brace matching turned off, the highlight of braces ends and is not given again")
                        : NAME("with all matching turned off, the highlight ends and is not given again"));
            [SUD setBool:YES forKey:CheckBraceEnabledKey];
            [view setSelectedRange:NSMakeRange(5, 0)]; Spin(0.01);
            [view setSelectedRange:NSMakeRange(6, 0)]; Spin(0.05);
            Check(LIT(5) && LIT(9) && EACH([Background(v, 7) isEqual:contentColor]), NAME("turned on again, braces are highlighted"));
            // Turned off and the insertion point moved, with no coloring in between.
            for (NSString *key in (which ? @[CheckBraceEnabledKey] : kinds)) [SUD setBool:NO forKey:key];
            [view setSelectedRange:NSMakeRange(1, 0)]; Spin(0.05);
            Check(UNLIT(5) && UNLIT(9) && EACH(Background(v, 6) == nil && [Background(v, 7) isEqual:fullwidthBackground]),
                  NAME("moving the insertion point after matching is turned off ends the highlight"));
            [SUD setBool:YES forKey:CheckBraceEnabledKey];
        }
        // Highlighting the contents turned off while they are highlighted.
        Show(@"abc\nx{a\uff11b}z\uff12\nxyz\n");
        Pass(5, 6); Spin(0.05);
        [SUD setBool:NO forKey:HighlightContentEnabledKey];
        Recolor(); Spin(0.05);
        Check(LIT(5) && LIT(9) && EACH(Background(v, 6) == nil && [Background(v, 7) isEqual:fullwidthBackground]),
              NAME("with Highlight Contents turned off, coloring ends the contents highlight and keeps the braces"));
        [SUD setBool:YES forKey:HighlightContentEnabledKey];
        for (int always = 0; always < 2; always++) {
            [SUD setBool:always forKey:AlwaysHighlightEnabledKey];
            Show(@"abc\nx{a\uff11b}z\uff12\nxyz\n");
            Pass(5, 6); Spin(0.05);
            // The closing brace replaced, the insertion point staying where it is.
            if ([view shouldChangeTextInRange:NSMakeRange(9, 1) replacementString:@"Q"]) {
                [view.textStorage replaceCharactersInRange:NSMakeRange(9, 1) withString:@"Q"];
                [view didChangeText];
            }
            Check(NSEqualRanges(view.selectedRange, NSMakeRange(6, 0)), NAME("the insertion point stays"));
            Spin(0.55); Recolor(); Spin(0.05);
            Check(UNLIT(9) && UNLIT(5) && EACH(Background(v, 6) == nil && [Background(v, 7) isEqual:fullwidthBackground] && Background(v, 9) == nil),
                  NAME("a highlighted brace replaced without moving the insertion point ends the highlight"));
        }
        [SUD setBool:NO forKey:HighlightContentEnabledKey];
        [SUD setBool:NO forKey:AlwaysHighlightEnabledKey];

        // 9. The active line keeps the fullwidth backgrounds and the highlighted contents on it and elsewhere.
        for (int scheme = 0; scheme < 2; scheme++) {
            NSDictionary *oldEntry = doc.EntryColorAttribute, *oldFullwidth = doc.fullwidthSymbolColorAttribute, *oldContent = highlightContentColorDict;
            NSColor *line = scheme ? NSColor.darkGrayColor : entryColor, *wide = scheme ? NSColor.systemTealColor : fullwidthBackground,
                    *contents = scheme ? NSColor.systemIndigoColor : contentColor;
            doc.EntryColorAttribute = @{NSBackgroundColorAttributeName: line};
            doc.fullwidthSymbolColorAttribute = @{NSForegroundColorAttributeName: fullwidthColor, NSBackgroundColorAttributeName: wide};
            highlightContentColorDict = @{NSBackgroundColorAttributeName: contents};
            doc.syntaxcolorEntry = YES;
            [SUD setBool:YES forKey:AlwaysHighlightEnabledKey]; [SUD setBool:YES forKey:HighlightContentEnabledKey];
            Show(@"\uff11a\nx{a\uff12b}z\uff13\nplain\n");
            NSTextView *lineView = view;
            void (^Cursor)(NSUInteger) = ^(NSUInteger at) { [lineView setSelectedRange:NSMakeRange(at, 0)]; Spin(0.02); [doc cursorMoved:lineView]; };
            Cursor(14);
            Check([Background(view, 0) isEqual:wide] && [Background(view, 10) isEqual:wide] && [Background(view, 13) isEqual:line] && Background(view, 1) == nil,
                  NAME("on a plain active line, fullwidth characters on other lines keep their background"));
            Cursor(1);
            Check([Background(view, 0) isEqual:wide] && [Background(view, 1) isEqual:line] && [Background(view, 10) isEqual:wide],
                  NAME("a fullwidth character on the active line keeps its background over the line's color"));
            Cursor(4); Cursor(5);
            Spin(0.05); [doc cursorMoved:view];
            Check([Background(view, 3) isEqual:line] && [Background(view, 5) isEqual:contents] && [Background(view, 6) isEqual:contents]
                  && [Background(view, 10) isEqual:wide] && [Background(view, 0) isEqual:wide] && LIT(4) && LIT(8),
                  NAME("highlighted contents show on the active line, over a fullwidth character too"));
            if (!inExperiment) {
                [doc cursorMoved:lower];
                Check([Background(lower, 6) isEqual:contents] && [Background(lower, 0) isEqual:wide], "lower half: the same with the active line drawn there");
            }
            // Syntax coloring of the document turned off while the contents are highlighted: the highlight
            // ends, the fullwidth backgrounds go, and the active line keeps its color once all that was
            // put off is done; on again, as before.
            if (scheme == 0) {
                [doc toggleSyntaxColor:nil]; Spin(0.30);
                Check(!doc.syntaxColor && [Background(view, 3) isEqual:line] && [Background(view, 9) isEqual:line] && [Background(view, 10) isEqual:line]
                      && Background(view, 0) == nil && Background(view, 13) == nil,
                      NAME("syntax coloring off while contents are highlighted: the active line keeps its color, no fullwidth background"));
                [doc toggleSyntaxColor:nil]; Spin(0.05);
                Cursor(4); Cursor(5); Spin(0.05); [doc cursorMoved:view];
                Check(doc.syntaxColor && [Background(view, 3) isEqual:line] && [Background(view, 6) isEqual:contents] && [Background(view, 0) isEqual:wide],
                      NAME("syntax coloring on again: the contents, the active line and fullwidth backgrounds as before"));
            }
            [view setSelectedRange:NSMakeRange(14, 0)]; Spin(0.05); [doc cursorMoved:view];
            Check(Background(view, 5) == nil && [Background(view, 6) isEqual:wide] && [Background(view, 13) isEqual:line],
                  NAME("when the contents highlight ends, the active line and fullwidth backgrounds remain"));
            // Block cursor: the cursor shows over a fullwidth character.
            doc.blockCursor = YES;
            [SUD setInteger:0 forKey:BlockWidthKey]; [SUD setInteger:2 forKey:BlockSideKey];
            [SUD setFloat:1 forKey:BlockCursorRKey]; [SUD setFloat:0 forKey:BlockCursorGKey]; [SUD setFloat:0 forKey:BlockCursorBKey];
            Cursor(0);
            NSColor *cursor = Background(view, 0);
            Check(cursor && ![cursor isEqual:wide] && [Background(view, 10) isEqual:wide], NAME("the block cursor shows over a fullwidth character, other ones keep their background"));
            doc.blockCursor = NO;
            // A theme without fullwidth colors: the active line alone.
            doc.fullwidthSymbolColorAttribute = nil;
            Recolor(); Cursor(14);
            Check(Background(view, 0) == nil && Background(view, 10) == nil && [Background(view, 13) isEqual:line], NAME("without fullwidth colors, only the active line has a background"));
            doc.syntaxcolorEntry = NO;
            [doc removeCurrentLineColor:view]; if (!inExperiment) [doc removeCurrentLineColor:lower];
            doc.EntryColorAttribute = oldEntry; doc.fullwidthSymbolColorAttribute = oldFullwidth; highlightContentColorDict = oldContent;
            [SUD setBool:NO forKey:AlwaysHighlightEnabledKey]; [SUD setBool:NO forKey:HighlightContentEnabledKey];
            Recolor(); Spin(0.40);
        }

        // 10. Changing the theme, or one of its colors in Settings (each step of a dragged color
        // well posts a change), keeps the highlights, in the new colors, light and dark.
        {
            NSArray *keys = @[@"EntryColorAttribute", @"commandColorAttribute", @"commentColorAttribute", @"explColorAttribute1", @"explColorAttribute2",
                              @"explColorAttribute3", @"explColorAttribute4", @"explColorAttribute5", @"explColorAttribute6", @"explColorAttribute7",
                              @"footnoteColorAttribute", @"fullwidthSymbolColorAttribute", @"indexColorAttribute", @"markerColorAttribute",
                              @"markerColorCurlyAttribute", @"markerColorParenAttribute", @"markerColorSquareAttribute", @"regularColorAttribute"];
            NSMutableDictionary *saved = [NSMutableDictionary dictionary];
            for (NSString *key in keys) { id value = [doc valueForKey:key]; if (value) saved[key] = value; }
            NSDictionary *savedBraces = highlightBracesColorDict, *savedContents = highlightContentColorDict, *savedLite = liteColors, *savedDark = darkColors;
            NSColor *(^Color)(NSArray *) = ^NSColor *(NSArray *c) {
                return [NSColor colorWithSRGBRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:1];
            };
            for (int dark = 0; dark < 2; dark++) {
                NSAppearance *appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                for (NSTextView *v in @[source, lower, scrap]) v.appearance = appearance;
                mainWindow.appearance = appearance;
                for (int always = 0; always < 2; always++) {
                    [SUD setBool:always forKey:AlwaysHighlightEnabledKey]; [SUD setBool:YES forKey:HighlightContentEnabledKey];
                    Show(@"abc\nx{a\uff11b}z\uff12\nxyz\n");
                    Pass(5, 6); Spin(0.05);
                    for (int step = 0; step < 3; step++) {
                        double s = 0.1 * step + (dark ? 0.05 : 0);
                        NSArray *contents = @[@(0.2 + s), @0.9, @0.9], *braces = @[@0.8, @(0.1 + s), @0.6], *wide = @[@0.5, @0.5, @(0.2 + s)];
                        NSDictionary *theme = @{@"theme": @YES, @"EditorHighlightContent": contents, @"EditorHighlightBraces": braces,
                                                @"EditorHighlightZenkakuSymbol": @[@0.4, @0.1, @0.4], @"EditorHighlightZenkakuSymbolBackground": wide,
                                                @"SyntaxComment": @[@0.8, @0.1, @0.1], @"EntryColor": @[@1, @1, @0.5]};
                        if (dark) darkColors = theme; else liteColors = theme;
                        [NSNotificationCenter.defaultCenter postNotificationName:@"SourceColorChangedNotification" object:nil];
                        Spin(0.01);
                        Check(EACH([Background(v, 6) isEqual:Color(contents)] && [Background(v, 7) isEqual:Color(contents)]
                                   && [Background(v, 11) isEqual:Color(wide)]),
                              NAME("a change of a theme color keeps the contents highlighted, in the new color"));
                        Check(EACH([Foreground(v, 5) isEqual:Color(braces)] && [Foreground(v, 9) isEqual:Color(braces)]),
                              NAME("and the braces too"));
                    }
                    if (!always) {
                        Spin(0.40);
                        [NSNotificationCenter.defaultCenter postNotificationName:@"SourceColorChangedNotification" object:nil];
                        Spin(0.01);
                        Check(EACH(![Foreground(v, 5) isEqual:[highlightBracesColorDict objectForKey:NSForegroundColorAttributeName]]
                                   && [Background(v, 7) isEqual:[highlightContentColorDict objectForKey:NSBackgroundColorAttributeName]]),
                              NAME("Flash: after the braces go out, a change of color keeps the contents highlighted"));
                    }
                    [view setSelectedRange:NSMakeRange(0, 0)]; Spin(0.40);
                }
            }
            for (NSTextView *v in @[source, lower, scrap]) v.appearance = nil;
            mainWindow.appearance = nil;
            liteColors = savedLite; darkColors = savedDark;
            for (NSString *key in keys) [doc setValue:saved[key] forKey:key];
            highlightBracesColorDict = savedBraces; highlightContentColorDict = savedContents;
            [SUD setBool:NO forKey:AlwaysHighlightEnabledKey]; [SUD setBool:NO forKey:HighlightContentEnabledKey];
            Recolor(); Spin(0.40);
        }

        // 11. Highlight Fullwidth Letters and Symbols turned off (Settings, Editor, Syntax Coloring; on in the
        // factory defaults): fullwidth letters, digits and symbols and the minus sign are colored exactly as the
        // same text is by a theme without fullwidth colors, by every kind of coloring again, light and dark; the
        // theme keeps its fullwidth colors for when the switch is on again. Settings posts the change
        // (TSPreferenceEffects.h), and the document colors its views again.
        {
            NSDictionary *savedTheme = SaveTheme();
            NSColor *(^RGB)(NSArray *) = ^NSColor *(NSArray *c) {
                return [NSColor colorWithSRGBRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:1];
            };
            Check(TSIsolatedAppKitDefaults.values[HighlightFullwidthSymbolsKey] == nil && [SUD boolForKey:HighlightFullwidthSymbolsKey],
                  NAME("Highlight Fullwidth Letters and Symbols is on without a setting of the user's"));
            void (^Switch)(BOOL) = ^(BOOL on) {
                [SUD setBool:on forKey:HighlightFullwidthSymbolsKey];
                if (@@FULLWIDTH_RECOLORS@@)
                    [NSNotificationCenter.defaultCenter postNotificationName:@"NeedsForRecolorNotification" object:nil];
                Spin(0.02);
            };
            // The colors of every character, in each view of the text.
            NSArray *(^Snapshot)(void) = ^NSArray *{
                NSMutableArray *all = [NSMutableArray array];
                for (NSTextView *v in views)
                    for (NSUInteger i = 0; i < v.string.length; i++) {
                        NSDictionary *a = [v.layoutManager temporaryAttributesAtCharacterIndex:i effectiveRange:NULL];
                        [all addObject:@[a[NSForegroundColorAttributeName] ?: NSNull.null, a[NSBackgroundColorAttributeName] ?: NSNull.null,
                                         a[TSFullwidthBackgroundMark] ? @YES : @NO]];
                    }
                return all;
            };
            NSUInteger (^Where)(NSString *) = ^NSUInteger(NSString *s) { return [view.string rangeOfString:s].location; };
            // A character colored as the one at another place, in each view.
            BOOL (^AsAt)(NSUInteger, NSUInteger) = ^BOOL(NSUInteger i, NSUInteger j) {
                if (i == NSNotFound || j == NSNotFound) return NO;
                return EACH((Foreground(v, i) == Foreground(v, j) || [Foreground(v, i) isEqual:Foreground(v, j)]) &&
                            (Background(v, i) == Background(v, j) || [Background(v, i) isEqual:Background(v, j)]));
            };
            NSString *text = @"x\uff0by x\uff11y x\u2212y\n\\a\uff22x \\\uff21 %a\uff21\na{\uff23}b plain\n";
            for (int dark = 0; dark < 2; dark++) {
                NSAppearance *appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                for (NSTextView *v in @[source, lower, scrap]) v.appearance = appearance;
                mainWindow.appearance = appearance;
                NSArray *wideText = dark ? @[@0.3, @0.9, @1] : @[@0.7, @0.1, @0], *wideBack = dark ? @[@0.1, @0, @0] : @[@0.9, @1, @1];
                NSDictionary *theme = @{@"theme": @YES, @"EditorHighlightZenkakuSymbol": wideText, @"EditorHighlightZenkakuSymbolBackground": wideBack,
                                        @"SyntaxComment": @[@0.8, @0.1, @0.1], @"SyntaxCommand": @[@0.1, @0.1, @0.8],
                                        @"EditorHighlightContent": @[@0.2, @0.9, @0.9], @"EditorHighlightBraces": @[@0.8, @0.1, @0.6], @"EntryColor": @[@1, @1, @0.5]};
                NSMutableDictionary *noFullwidth = [theme mutableCopy];
                [noFullwidth removeObjectsForKeys:@[@"EditorHighlightZenkakuSymbol", @"EditorHighlightZenkakuSymbolBackground"]];
                NSMutableDictionary *otherWide = [theme mutableCopy];
                otherWide[@"EditorHighlightZenkakuSymbol"] = @[@0.2, @0.6, @0.2]; otherWide[@"EditorHighlightZenkakuSymbolBackground"] = @[@0.6, @0.6, @0.9];
                void (^Theme)(NSDictionary *) = ^(NSDictionary *t) {
                    if (dark) darkColors = t; else liteColors = t;
                    [NSNotificationCenter.defaultCenter postNotificationName:@"SourceColorChangedNotification" object:nil];
                    Spin(0.01);
                };
                NSArray *wideColors = @[RGB(wideText), RGB(wideBack), RGB(otherWide[@"EditorHighlightZenkakuSymbol"]), RGB(otherWide[@"EditorHighlightZenkakuSymbolBackground"])];
                // No character anywhere in the text has a fullwidth color or the mark of a fullwidth background.
                BOOL (^NoneWide)(void) = ^BOOL {
                    for (NSTextView *v in views)
                        for (NSUInteger i = 0; i < v.string.length; i++) {
                            NSDictionary *a = [v.layoutManager temporaryAttributesAtCharacterIndex:i effectiveRange:NULL];
                            if (a[TSFullwidthBackgroundMark] || [wideColors containsObject:a[NSForegroundColorAttributeName] ?: NSNull.null]
                                || [wideColors containsObject:a[NSBackgroundColorAttributeName] ?: NSNull.null])
                                return NO;
                        }
                    return YES;
                };
                // Off: no fullwidth colors, and fullwidth characters colored as their neighbors.
                BOOL (^Plain)(void) = ^BOOL {
                    NSUInteger plus = Where(@"x\uff0by"), one = Where(@"x\uff11y"), minus = Where(@"x\u2212y"), b = Where(@"\uff22x"), c = Where(@"\uff23}b");
                    return NoneWide() && AsAt(plus + 1, plus) && AsAt(one + 1, one) && AsAt(minus + 1, minus) && AsAt(b, b + 1) && AsAt(c, c + 2);
                };
                // On: those outside comments and commands in the theme's fullwidth colors.
                BOOL (^Wide)(void) = ^BOOL {
                    BOOL all = YES;
                    for (NSString *s in @[@"\uff0b", @"\uff11", @"\u2212", @"\uff22", @"\uff23"]) {
                        NSUInteger i = Where(s);
                        if (!EACH([Foreground(v, i) isEqual:RGB(wideText)] && [Background(v, i) isEqual:RGB(wideBack)])) all = NO;
                    }
                    return all;
                };

                // Turned off and on: the colors of a theme without fullwidth colors, then the colors as before.
                Theme(noFullwidth);
                Show(text);
                NSArray *plain = Snapshot();
                Theme(theme);
                Show(text);
                NSArray *wide = Snapshot();
                Check(Wide() && ![wide isEqual:plain], NAME("fullwidth characters have the theme's colors"));
                Check(AsAt(Where(@"a\uff21\n") + 1, Where(@"a\uff21\n")), NAME("a fullwidth character in a comment has the comment's color"));
                Switch(NO);
                Check([Snapshot() isEqual:plain], NAME("turned off, the text has the colors of a theme without fullwidth colors"));
                Check(Plain(), NAME("turned off, fullwidth characters are colored as their neighbors"));
                Switch(YES);
                Check([Snapshot() isEqual:wide], NAME("turned on again, the text has its fullwidth colors again"));
                Switch(NO);

                // Whatever colors the text again, fullwidth characters stay colored as other text.
                NSMutableArray *paths = [@[@"type", @"type fullwidth", @"paste", @"resize", @"scroll", @"settings", @"recolor", @"theme", @"comment", @"uncomment"] mutableCopy];
                if (!inExperiment) [paths insertObject:@"undo" atIndex:3];
                if (!inExperiment) [paths insertObject:@"lower half resize" atIndex:5];
                for (NSString *path in paths) {
                    if ([path isEqual:@"type"]) {
                        [view setSelectedRange:NSMakeRange(0, 0)];
                        [view insertText:@"q" replacementRange:NSMakeRange(NSNotFound, 0)];
                    } else if ([path isEqual:@"type fullwidth"]) {
                        [view setSelectedRange:NSMakeRange(Where(@"plain"), 0)];
                        [view insertText:@"\uff10" replacementRange:NSMakeRange(NSNotFound, 0)];
                    } else if ([path isEqual:@"paste"]) {
                        NSPasteboard *board = [NSPasteboard pasteboardWithUniqueName];
                        [board clearContents];
                        [board setString:@"x\uff15y" forType:NSPasteboardTypeString];
                        [view setSelectedRange:NSMakeRange(Where(@"plain"), 0)];
                        [view readSelectionFromPasteboard:board type:NSPasteboardTypeString];
                        [board releaseGlobally];
                    } else if ([path isEqual:@"undo"]) [view.undoManager undo];
                    else if ([path isEqual:@"resize"]) [doc viewFrameDidChange:[NSNotification notificationWithName:NSViewFrameDidChangeNotification object:view]];
                    else if ([path isEqual:@"lower half resize"]) [doc viewFrameDidChange:[NSNotification notificationWithName:NSViewFrameDidChangeNotification object:lower]];
                    else if ([path isEqual:@"scroll"]) [doc viewBoundsDidChange:[NSNotification notificationWithName:NSViewBoundsDidChangeNotification object:view.enclosingScrollView.contentView]];
                    else if ([path isEqual:@"settings"]) [doc reColor:nil];
                    else if ([path isEqual:@"recolor"]) Recolor();
                    else if ([path isEqual:@"theme"]) { Theme(otherWide); Check(NoneWide(), NAME("a theme with other fullwidth colors gives none")); Theme(theme); }
                    else if ([path isEqual:@"comment"] || [path isEqual:@"uncomment"]) {
                        // As -doCommentOrIndentForTag: does: the edit, then the lines are colored again.
                        BOOL comment = [path isEqual:@"comment"];
                        [view replaceCharactersInRange:NSMakeRange(0, comment ? 0 : 1) withString:comment ? @"%" : @""];
                        if (inExperiment) [doc colorizeExperimentSource]; else [doc fixColor:0 :Where(@"\n") + 1];
                    }
                    Spin(0.05);
                    if ([path isEqual:@"comment"]) {
                        NSUInteger plus = Where(@"x\uff0by");
                        Check(NoneWide() && AsAt(plus + 1, plus) && AsAt(plus + 1, 0), NAME("off: commented out, a fullwidth character has the comment's color"));
                        continue;
                    }
                    if (!Plain()) printf("   after %s\n", path.UTF8String);
                    Check(Plain(), NAME("off: coloring again keeps fullwidth characters colored as other text"));
                    if ([path isEqual:@"type fullwidth"])
                        Check(AsAt(Where(@"\uff10"), Where(@"\uff10") + 1), NAME("off: a typed fullwidth digit is colored as other text"));
                    if ([path isEqual:@"paste"])
                        Check(AsAt(Where(@"x\uff15y") + 1, Where(@"x\uff15y")), NAME("off: a pasted fullwidth digit is colored as other text"));
                }
                Switch(YES);
                Check(Wide() && [Background(view, Where(@"\uff10")) isEqual:RGB(wideBack)], NAME("on again after the edits, fullwidth characters have their colors"));
                Switch(NO);

                // Syntax coloring of the document (Source menu) turned off and on, before or after the switch,
                // with and without the active line: off, the text has no fullwidth colors nor their marks, and a
                // fullwidth character on the active line has the line's color; on again, the switch decides.
                for (int entry = 0; entry < 2; entry++)
                    for (int order = 0; order < 4; order++) {
                        void (^Syntax)(BOOL) = ^(BOOL on) { if (doc.syntaxColor != on) [doc toggleSyntaxColor:nil]; Spin(0.02); };
                        Syntax(YES);
                        Switch(order != 2);
                        doc.syntaxcolorEntry = entry;
                        Show(text);
                        [view setSelectedRange:NSMakeRange(1, 0)]; Spin(0.02);
                        for (NSTextView *v in views) [doc cursorMoved:v];
                        BOOL ok = YES;
                        if (order == 1) { Switch(NO); ok &= Plain(); }
                        Syntax(NO);
                        ok &= Plain() && (!entry || Background(view, Where(@"x\uff0by")) != nil);
                        if (order == 0) { Switch(NO); ok &= Plain(); }
                        if (order == 2) { Switch(YES); ok &= Plain(); }
                        Syntax(YES);
                        ok &= (order == 0 || order == 1) ? Plain() : Wide();
                        Switch(YES);
                        ok &= Wide();
                        const char *names[] = {"syntax coloring off, then the switch off", "the switch off, then syntax coloring off",
                                               "switch off, syntax coloring off, switch on", "syntax coloring off and on with the switch on"};
                        char name[240];
                        snprintf(name, sizeof name, "%s %s%s: no fullwidth colors while syntax coloring is off, the switch decides once it is on",
                                 inExperiment ? "Experiment:" : "source:", names[order], entry ? ", with the active line" : "");
                        Check(ok, name);
                        doc.syntaxcolorEntry = NO;
                        for (NSTextView *v in views) [doc removeCurrentLineColor:v];
                    }
                Switch(NO);

                // The active line: a fullwidth character on it has the line's color, as its neighbors.
                doc.syntaxcolorEntry = YES;
                Show(text);
                [view setSelectedRange:NSMakeRange(1, 0)]; Spin(0.02);
                for (NSTextView *v in views) [doc cursorMoved:v];
                NSUInteger plus = Where(@"x\uff0by");
                Check(Plain() && Background(view, plus) != nil && AsAt(plus + 1, plus), NAME("off: on the active line, a fullwidth character has the line's color"));
                Switch(YES);
                for (NSTextView *v in views) [doc cursorMoved:v];
                Check([Background(view, Where(@"\uff23")) isEqual:RGB(wideBack)] && [Background(view, plus + 1) isEqual:RGB(wideBack)],
                      NAME("on: fullwidth characters keep their background on the active line and elsewhere"));
                Switch(NO);
                for (NSTextView *v in views) [doc cursorMoved:v];
                Check(Plain() && Background(view, Where(@"\uff23")) == nil, NAME("off again with the active line: no fullwidth background anywhere"));
                doc.syntaxcolorEntry = NO;
                for (NSTextView *v in views) [doc removeCurrentLineColor:v];

                // The highlight of braces and of their contents: a fullwidth digit inside has the contents' color,
                // one outside none; when the highlight ends, neither has a background.
                [SUD setBool:YES forKey:HighlightContentEnabledKey];
                for (int always = 0; always < 2; always++) {
                    [SUD setBool:always forKey:AlwaysHighlightEnabledKey];
                    Show(@"abc\nx{a\uff11b}z\uff12\nxyz\n");
                    Pass(5, 6); Spin(0.05);
                    Check(CONTENTS && AsAt(7, 6) && AsAt(11, 10) && NoneWide() && EACH(Background(v, 7) != nil), NAME("off: highlighted contents color a fullwidth digit as the other contents"));
                    Recolor(); Spin(0.02);
                    Check(AsAt(7, 6) && AsAt(11, 10) && NoneWide(), NAME("off: and so after coloring again"));
                    Switch(YES);
                    Check(EACH([Background(v, 7) isEqual:Background(v, 6)]) && [Background(view, 11) isEqual:RGB(wideBack)], NAME("turned on during the highlight: the contents keep their color, the digit outside gets its own"));
                    Switch(NO);
                    Check(AsAt(7, 6) && AsAt(11, 10) && NoneWide(), NAME("turned off during the highlight: the contents keep their color"));
                    [view setSelectedRange:NSMakeRange(0, 0)]; Spin(0.40);
                    Check(!CONTENTS && EACH(Background(v, 7) == nil) && AsAt(7, 6) && NoneWide(), NAME("off: when the highlight ends, the fullwidth digit has no background"));
                }
                [SUD setBool:NO forKey:HighlightContentEnabledKey]; [SUD setBool:NO forKey:AlwaysHighlightEnabledKey];

                // The flash for an unmatched brace.
                [SUD setBool:YES forKey:FlashBackgroundEnabledKey];
                Show(@"x\uff11y\nx}}y\n");
                Pass(5, 6); Spin(0.02);
                Spin(0.35);
                Check(NoneWide() && AsAt(1, 0), NAME("off: after the flash for an unmatched brace, a fullwidth digit is colored as other text"));
                [SUD setBool:NO forKey:FlashBackgroundEnabledKey];

                // Turned off or on while text is composed: the text is colored once the composed text is
                // committed or removed, in every view.
                for (int step = 0; step < 4; step++) {
                    BOOL commit = step % 2, turnOn = step / 2;
                    Switch(!turnOn);
                    Show(text);
                    [view setSelectedRange:NSMakeRange(0, 0)];
                    Compose(view, @[@"\u3042"]);
                    Switch(turnOn);
                    Check(view.hasMarkedText, NAME("text is being composed"));
                    if (commit) [view insertText:@"\u4e9c" replacementRange:NSMakeRange(NSNotFound, 0)];
                    else { [view setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)]; [view unmarkText]; }
                    Spin(0.05);
                    Check(!view.hasMarkedText && (turnOn ? Wide() : Plain()),
                          turnOn ? NAME("turned on while text is composed: the fullwidth colors once it is committed or removed")
                                 : NAME("turned off while text is composed: no fullwidth colors once it is committed or removed"));
                }
                Switch(NO);

                // Lines out of sight: colored as they come into view, also after a change made while composing.
                for (int composing = 0; composing < 2; composing++) {
                    for (int on = 0; on < 2; on++) {
                        Switch(on);
                        NSMutableString *longText = Source();
                        [longText appendString:@"x\uff11y\n"];
                        Show(longText);
                        NSUInteger end = longText.length - 3;
                        [view scrollRangeToVisible:NSMakeRange(end, 1)]; Spin(0.05);
                        [doc viewBoundsDidChange:[NSNotification notificationWithName:NSViewBoundsDidChangeNotification object:view.enclosingScrollView.contentView]];
                        BOOL before = on ? [Background(view, end) isEqual:RGB(wideBack)] : Background(view, end) == nil;
                        [view scrollRangeToVisible:NSMakeRange(0, 0)]; Spin(0.05);
                        [doc viewBoundsDidChange:[NSNotification notificationWithName:NSViewBoundsDidChangeNotification object:view.enclosingScrollView.contentView]];
                        if (composing) { [view setSelectedRange:NSMakeRange(0, 0)]; Compose(view, @[@"\u3042"]); }
                        Switch(!on);
                        if (composing) { [view insertText:@"\u4e9c" replacementRange:NSMakeRange(NSNotFound, 0)]; Spin(0.05); end++; }
                        [view scrollRangeToVisible:NSMakeRange(end, 1)]; Spin(0.05);
                        [doc viewBoundsDidChange:[NSNotification notificationWithName:NSViewBoundsDidChangeNotification object:view.enclosingScrollView.contentView]];
                        // Only this view scrolls: the other half of a split window shows the beginning still.
                        NSDictionary *a = [view.layoutManager temporaryAttributesAtCharacterIndex:end effectiveRange:NULL];
                        NSDictionary *x = [view.layoutManager temporaryAttributesAtCharacterIndex:end - 1 effectiveRange:NULL];
                        BOOL after = !on ? ([a[NSForegroundColorAttributeName] isEqual:RGB(wideText)] && [a[NSBackgroundColorAttributeName] isEqual:RGB(wideBack)])
                                         : (a[TSFullwidthBackgroundMark] == nil && (a[NSForegroundColorAttributeName] == x[NSForegroundColorAttributeName] || [a[NSForegroundColorAttributeName] isEqual:x[NSForegroundColorAttributeName]])
                                            && (a[NSBackgroundColorAttributeName] == x[NSBackgroundColorAttributeName] || [a[NSBackgroundColorAttributeName] isEqual:x[NSBackgroundColorAttributeName]]));
                        Check(before && after, on ? NAME("turned off, a line out of sight shows no fullwidth colors when it comes into view")
                                                  : NAME("turned on, a line out of sight shows the fullwidth colors when it comes into view"));
                    }
                }
                Switch(YES);
                RestoreTheme(savedTheme);
                Recolor();
            }
            for (NSTextView *v in @[source, lower, scrap]) v.appearance = nil;
            mainWindow.appearance = nil;
            [SUD removeObjectForKey:HighlightFullwidthSymbolsKey];
            RestoreTheme(savedTheme);
            Recolor(); Spin(0.40);
        }

        // 12. Removing the color of the active line (Highlight Current Line turned off, the window split, or the
        // Experiment source colored when composed text that coloring waited for ends) leaves the fullwidth
        // backgrounds and the highlighted contents.
        [SUD setBool:YES forKey:AlwaysHighlightEnabledKey]; [SUD setBool:YES forKey:HighlightContentEnabledKey];
        Show(@"abc\nx{a\uff11b}z\uff12\nxyz\n");
        Pass(5, 6); Spin(0.05);
        doc.syntaxcolorEntry = YES;
        for (NSTextView *v in views) [doc cursorMoved:v];
        doc.syntaxcolorEntry = NO;
        for (NSTextView *v in views) [doc removeCurrentLineColor:v];
        Check(EACH([Background(v, 7) isEqual:contentColor] && [Background(v, 11) isEqual:fullwidthBackground] && Background(v, 4) == nil),
              NAME("the active line's color removed, highlighted contents and fullwidth backgrounds remain"));
        [view setSelectedRange:NSMakeRange(0, 0)]; Spin(0.40);
        [SUD setBool:NO forKey:AlwaysHighlightEnabledKey]; [SUD setBool:NO forKey:HighlightContentEnabledKey];
        for (int commit = 0; commit < 2; commit++) {
            Show(@"x\uff11y\nabc\n");
            [view setSelectedRange:NSMakeRange(8, 0)];
            Compose(view, @[@"\u3042"]);
            Recolor();  // as a resize, a scroll or a change of settings does while text is composed
            if (commit) [view insertText:@"\u4e9c" replacementRange:NSMakeRange(NSNotFound, 0)];
            else { [view setMarkedText:@"" selectedRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, 0)]; [view unmarkText]; }
            Spin(0.05);
            Check(!view.hasMarkedText && EACH([Background(v, 1) isEqual:fullwidthBackground]),
                  NAME("after composed text that coloring waited for, fullwidth characters keep their background"));
        }
        if (!inExperiment) [mainWindow makeFirstResponder:source];
    }

    if (failures) return 1;
    printf("PASS: brace highlights and backgrounds go away when they should, and only then, in both halves of the source "
           "and in the Experiment source\n");
} return 0; }
'''
replacements = {
    'DEFINES': defines, 'SCRAP_OVERRIDES': scrap_overrides, 'TAB_STOPS': tab_stops, 'BRACE_SEARCH': brace_search,
    'DOCUMENT_METHODS': document_methods, 'TOGGLE_XML': toggle_xml, 'TEXT_VIEW_TABS': text_view_tabs, 'SYNTAX': strip_imports(text[SYNTAX]), 'EXPERIMENT': strip_imports(text[EXPERIMENT]), 'COLOR': strip_imports(text[COLOR]),
    'TRY_SCRAP_SYNCS': 'YES' if '[self syncExperimentSourceDisplay];' in try_scrap else 'NO',
    'FULLWIDTH_FACTORY': factory_fullwidth, 'FULLWIDTH_RECOLORS': 'YES' if fullwidth_recolors else 'NO',
    'OBSERVES_RECOLOR': 'YES' if observes_recolor else 'NO',
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
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=400)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
