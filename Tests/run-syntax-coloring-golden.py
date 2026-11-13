#!/usr/bin/env python3
"""The colors that syntax coloring gives the source stay exactly the same.

Sample documents (plain LaTeX, expl3, Japanese and fullwidth characters, XML,
right-to-left text, broken input, a real manual and a large document) are
colored with every combination of the settings that change the coloring:
expl3, index and footnote colors, \\makeatletter, the spelling exclusions, the
fullwidth highlight, the active line and block cursor, the yen sign as the TeX
character, XML and right justification. For each character the harness records
which color the layout manager shows (named after the document property it came
from, not by its value), the background, which characters lose their spelling
marks and the paragraph alignment. Each case is compared with
Tests/Fixtures/SyntaxColoringGolden.txt: in full for the small samples with the
plain settings, and by a SHA-256 of the same record otherwise.

The production category TSDocument (SyntaxHighlighting) and the XML coloring of
TSDocument (XML) are compiled unchanged onto a small TSDocument stand-in. Text
views use TextKit 1 and are never put in a window shown on screen. Preferences
stay in memory.

  --update         rewrite the golden file from the current sources
  --dump-all PATH  write the full record of every case, to compare two revisions
  --benchmark      time coloring a large document; nothing is compared
  --mutation NAME  check that a change of the coloring is detected
"""
from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys, tempfile, time
from source_tree import include_args, source_file
from production_fragments import method

ROOT = Path(__file__).resolve().parents[1]
SYNTAX = 'Sources/Editor/TSDocument-Syntax.m'
XML = 'Sources/Document/TSDocument-XML.m'
DELEGATE = 'Sources/App/TSAppDelegate.m'
FIXTURES = ROOT / 'Tests/Fixtures/SyntaxColoring'
GOLDEN = ROOT / 'Tests/Fixtures/SyntaxColoringGolden.txt'

MUTATIONS = {
    # A square bracket colored like a curly brace.
    'square-as-curly': (SYNTAX, '[layoutManager addTemporaryAttributes:self.markerColorSquareAttribute forCharacterRange:colorRange];',
                        '[layoutManager addTemporaryAttributes:self.markerColorCurlyAttribute forCharacterRange:colorRange];'),
    # The minus sign no longer highlighted as a fullwidth character.
    'no-minus-sign': (SYNTAX, ' || c == 0x2212;', ';'),
    # The character after a command whose parameters are not spell checked is scanned again.
    'rescan-after-parameters': (SYNTAX, 'spellLocation = location++;', 'spellLocation = location;'),
    # An XML comment one character shorter.
    'xml-comment-short': (XML, 'colorRange.length = search1Range.location - colorRange.location + 3;\n            [layoutManager',
                          'colorRange.length = search1Range.location - colorRange.location + 2;\n            [layoutManager'),
}

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
group = parser.add_mutually_exclusive_group()
group.add_argument('--update', action='store_true')
group.add_argument('--dump-all', metavar='PATH')
group.add_argument('--benchmark', action='store_true')
group.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

text = {path: (ROOT / path).read_text(encoding='latin1') for path in (SYNTAX, XML, DELEGATE)}
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert text[path].count(old) == 1, args.mutation
    text[path] = text[path].replace(old, new)


def strip_imports(source):
    return re.sub(r'^#import .*$', '', source, flags=re.M)


xml_methods = '\n'.join(method(text[XML], s) for s in [
    '- (BOOL) isValidLetter: (char) c',
    '- (void) syntaxColorXMLCommentsfrom: (NSUInteger) aLineStart',
    '- (void) syntaxColorXML: (NSUInteger *)location',
    '- (void) syntaxColorLimitedXML: (NSUInteger *)location'])
# The built-in lists of commands whose parameters are or are not spell checked.
spell_lists = '\n'.join(re.search(r'^\s*%s = \[\[NSArray alloc\] initWithObjects:.*?nil\];' % name, text[DELEGATE], re.M | re.S).group(0)
                        for name in ('commandsToSpellCheck', 'commandsNotToSpellCheck'))
globals_m = source_file(ROOT, 'globals.m').read_text(encoding='latin1')
keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
defines = '\n'.join(f'#define {k} {v}' for k, v in sorted(keys.items()))

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#define SUD TSIsolatedAppKitDefaults
@@DEFINES@@
#define MOJAVEORHIGHER
BOOL atLeastMojave = YES;
NSArray *commandsToSpellCheck, *userCommandsToSpellCheck, *commandsNotToSpellCheck, *userCommandsNotToSpellCheck;
NSInteger g_texChar = '\\';
static BOOL TeXAwareSpelling;
static void LoadSpellLists(void) {
@@SPELL_LISTS@@
}

// A source view; the characters whose spelling marks are removed are recorded.
@interface GoldenTextView : NSTextView
@property (strong) NSMutableIndexSet *unspelled;
@end
@implementation GoldenTextView
- (void)setSpellingState:(NSInteger)value range:(NSRange)range
{
    if (value == 0) [self.unspelled addIndexesInRange:range];
    [super setSpellingState:value range:range];
}
@end
@interface NSTextView (TSTestSpelling)
- (BOOL)usesTeXAwareSpellChecking;
@end
@implementation NSTextView (TSTestSpelling)
- (BOOL)usesTeXAwareSpellChecking { return TeXAwareSpelling; }
@end

@interface TSDocument : NSObject {
    @public
    BOOL tagLine, fileIsTex, isLoading, firstTime, indexColor, experimentShown;
    NSUInteger colorStart, colorEnd;
    NSTimeInterval colorTime;
    NSTextView *textView1, *textView2, *scrapTextView, *textView;
}
@property (strong) NSDictionary *EntryColorAttribute, *commandColorAttribute, *commentColorAttribute,
    *explColorAttribute1, *explColorAttribute2, *explColorAttribute3, *explColorAttribute4, *explColorAttribute5,
    *explColorAttribute6, *explColorAttribute7, *footnoteColorAttribute, *fullwidthSymbolColorAttribute,
    *indexColorAttribute, *markerColorAttribute, *markerColorCurlyAttribute, *markerColorParenAttribute,
    *markerColorSquareAttribute, *regularColorAttribute, *commentXMLColorAttribute, *tagXMLColorAttribute,
    *specialXMLColorAttribute, *parameterXMLColorAttribute, *valueXMLColorAttribute;
@property BOOL blockCursor, fileIsXML, syntaxColor, syntaxcolorEntry, useExplColor, coloringWaitsForMarkedText;
@property (strong) NSTextStorage *textStorage;
@property (strong) NSTextView *textView;
- (void)colorizeText:(NSTextView *)aTextView range:(NSRange)range;
- (void)colorizeAll;
- (void)colorizeVisibleAreaInTextView:(NSTextView *)aTextView;
- (void)fixColor:(NSUInteger)from :(NSUInteger)to;
- (void)reColor:(NSNotification *)notification;
- (void)cursorMoved:(NSTextView *)aTextView;
@end

@implementation TSDocument
@synthesize textView = textView;
- (IBAction)doUpdate:(id)sender {}
- (void)setupTags {}
- (BOOL)indexColorState { return indexColor; }
- (void)colorizeExperimentSource { if (experimentShown) [self colorizeVisibleAreaInTextView:scrapTextView]; }
- (void)refreshExperimentCurrentLine {}
@@XML_METHODS@@
@end

@@SYNTAX@@

static int failures;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }

// Every color the coloring can show is distinct, and is named after where it comes from.
static NSMutableDictionary<NSString *, NSString *> *ColorNames;
static NSMutableDictionary<NSString *, NSColor *> *NamedColors;
static NSColor *NamedColor(NSString *name)
{
    if (NamedColors[name]) return NamedColors[name];
    NSUInteger index = ColorNames.count + 1;
    NSCAssert(index < 200, @"few enough colors to tell apart");
    NSColor *color = [NSColor colorWithSRGBRed:index / 255.0 green:(255 - index) / 255.0 blue:0.5 alpha:1];
    ColorNames[[NSString stringWithFormat:@"%lu", (unsigned long)index]] = name;
    NamedColors[name] = color;
    return color;
}
static NSString *ColorName(NSColor *color)
{
    if (!color) return nil;
    NSColor *srgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSString *name = ColorNames[[NSString stringWithFormat:@"%ld", lround(srgb.redComponent * 255)]];
    return name ?: [NSString stringWithFormat:@"unknown(%@)", color];
}
static NSDictionary *Foreground(NSString *name) { return @{NSForegroundColorAttributeName: NamedColor(name)}; }

static NSColor *Sentinel, *SentinelBackground;
static void SetUpColors(TSDocument *doc, NSString *fullwidth)
{
    for (NSString *key in @[@"commandColorAttribute", @"commentColorAttribute", @"explColorAttribute1", @"explColorAttribute2",
                            @"explColorAttribute3", @"explColorAttribute4", @"explColorAttribute5", @"explColorAttribute6",
                            @"explColorAttribute7", @"footnoteColorAttribute", @"indexColorAttribute", @"markerColorAttribute",
                            @"markerColorCurlyAttribute", @"markerColorParenAttribute", @"markerColorSquareAttribute",
                            @"regularColorAttribute", @"commentXMLColorAttribute", @"tagXMLColorAttribute",
                            @"specialXMLColorAttribute", @"parameterXMLColorAttribute", @"valueXMLColorAttribute"])
        [doc setValue:Foreground([key stringByReplacingOccurrencesOfString:@"Attribute" withString:@""]) forKey:key];
    doc.EntryColorAttribute = @{NSBackgroundColorAttributeName: NamedColor(@"EntryColor")};
    NSColor *fullwidthForeground = NamedColor(@"fullwidthSymbol"), *fullwidthBackground = NamedColor(@"fullwidthSymbolBackground");
    if ([fullwidth isEqual:@"both"])
        doc.fullwidthSymbolColorAttribute = @{NSForegroundColorAttributeName: fullwidthForeground, NSBackgroundColorAttributeName: fullwidthBackground};
    else if ([fullwidth isEqual:@"foreground"])
        doc.fullwidthSymbolColorAttribute = @{NSForegroundColorAttributeName: fullwidthForeground};
    else
        doc.fullwidthSymbolColorAttribute = nil;
}

// TextKit 1, as in the source window: the text storage, its layout managers and the views.
static GoldenTextView *MakeView(NSTextStorage *storage, NSSize size)
{
    NSLayoutManager *layout = [NSLayoutManager new];
    layout.allowsNonContiguousLayout = YES;
    [storage addLayoutManager:layout];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(size.width, CGFLOAT_MAX)];
    container.widthTracksTextView = YES;
    [layout addTextContainer:container];
    GoldenTextView *view = [[GoldenTextView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height) textContainer:container];
    view.verticallyResizable = YES;
    view.unspelled = [NSMutableIndexSet indexSet];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = view;
    return view;
}

static NSString *Escape(NSString *s)
{
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\' || c == '"') [out appendFormat:@"\\%C", c];
        else if (c == '\n') [out appendString:@"\\n"];
        else if (c == '\r') [out appendString:@"\\r"];
        else if (c == '\t') [out appendString:@"\\t"];
        else if (c < 0x20 || (c >= 0x2028 && c <= 0x2029) || (c >= 0xD800 && c <= 0xDFFF)) [out appendFormat:@"\\u%04X", c];
        else [out appendFormat:@"%C", c];
    }
    return out;
}

// The record of one view: runs of the same foreground, background and spelling state.
static NSString *Record(GoldenTextView *view)
{
    NSString *string = view.string;
    NSLayoutManager *layout = view.layoutManager;
    NSUInteger length = string.length;
    NSMutableString *out = [NSMutableString string];
    for (NSString *kind in @[@"fg", @"bg"]) {
        NSAttributedStringKey key = [kind isEqual:@"fg"] ? NSForegroundColorAttributeName : NSBackgroundColorAttributeName;
        NSUInteger start = 0; NSString *current = nil;
        for (NSUInteger i = 0; i <= length; i++) {
            NSString *name = i < length ? ColorName([layout temporaryAttribute:key atCharacterIndex:i effectiveRange:NULL]) : nil;
            if (i == length || !(name == current || [name isEqual:current])) {
                if (current)
                    [out appendFormat:@"%@ %lu-%lu %@ \"%@\"\n", kind, (unsigned long)start, (unsigned long)i, current,
                        Escape([string substringWithRange:NSMakeRange(start, MIN(i - start, 40))])];
                start = i; current = name;
            }
        }
    }
    // Ranges past the end of the text, which the coloring sometimes asks for, show nothing.
    NSMutableIndexSet *unspelled = [view.unspelled mutableCopy];
    [unspelled removeIndexesInRange:NSMakeRange(length, NSNotFound - length)];
    [unspelled enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        [out appendFormat:@"nospell %lu-%lu \"%@\"\n", (unsigned long)range.location, (unsigned long)NSMaxRange(range),
            Escape([string substringWithRange:NSMakeRange(range.location, MIN(range.length, 40))])];
    }];
    NSTextStorage *storage = view.textStorage;
    for (NSUInteger i = 0; i < length; ) {
        NSRange paragraph = [string paragraphRangeForRange:NSMakeRange(i, 0)];
        NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:i effectiveRange:NULL];
        if (style && style.alignment != NSTextAlignmentNatural)
            [out appendFormat:@"align %lu %ld\n", (unsigned long)paragraph.location, (long)style.alignment];
        i = MAX(NSMaxRange(paragraph), i + 1);
    }
    return out;
}

static NSString *TemporaryState(NSTextView *view)
{
    // The colors of a view, by character, to compare views of the same text.
    NSMutableString *state = [NSMutableString string];
    NSLayoutManager *layout = view.layoutManager;
    for (NSUInteger i = 0; i < view.string.length; i++) {
        NSDictionary *a = [layout temporaryAttributesAtCharacterIndex:i effectiveRange:NULL];
        [state appendFormat:@"%@/%@;", ColorName(a[NSForegroundColorAttributeName]), ColorName(a[NSBackgroundColorAttributeName])];
    }
    return state;
}

// What other features left: every character starts with a foreground and a background.
static void Seed(NSTextView *view)
{
    NSRange all = NSMakeRange(0, view.string.length);
    [view.layoutManager addTemporaryAttributes:@{NSForegroundColorAttributeName: Sentinel, NSBackgroundColorAttributeName: SentinelBackground}
                             forCharacterRange:all];
}

static NSDictionary *Settings;
static BOOL Flag(NSString *key) { return [Settings[key] boolValue]; }

static TSDocument *MakeDocument(NSDictionary *settings, NSString *string, NSSize size)
{
    Settings = settings;
    for (NSString *key in @[MakeatletterEnabledKey, SyntaxColorFootnoteKey, TurnOffCommandSpellCheckKey, TurnOffCommentSpellCheckKey,
                            TurnOffParameterSpellCheckKey, ExceptionListExcludesParametersKey, AlwaysHighlightEnabledKey,
                            RightJustifyKey, RightJustifyIfAnyKey, ColorImmediatelyKey])
        [SUD removeObjectForKey:key];
    [SUD setBool:Flag(@"makeatletter") forKey:MakeatletterEnabledKey];
    [SUD setBool:Flag(@"footnote") forKey:SyntaxColorFootnoteKey];
    [SUD setBool:Flag(@"spellCommand") forKey:TurnOffCommandSpellCheckKey];
    [SUD setBool:Flag(@"spellComment") forKey:TurnOffCommentSpellCheckKey];
    [SUD setBool:Flag(@"spellParameter") forKey:TurnOffParameterSpellCheckKey];
    [SUD setBool:Flag(@"exceptionsList") forKey:ExceptionListExcludesParametersKey];
    [SUD setBool:Flag(@"alwaysHighlight") forKey:AlwaysHighlightEnabledKey];
    [SUD setBool:Flag(@"rightJustify") forKey:RightJustifyKey];
    [SUD setBool:Flag(@"rightJustifyIfAny") forKey:RightJustifyIfAnyKey];
    [SUD setInteger:[Settings[@"blockSide"] integerValue] forKey:BlockSideKey];
    [SUD setInteger:[Settings[@"blockWidth"] integerValue] forKey:BlockWidthKey];
    TeXAwareSpelling = Flag(@"texAware");
    userCommandsToSpellCheck = Settings[@"userChecked"] ?: @[];
    userCommandsNotToSpellCheck = Settings[@"userUnchecked"] ?: @[];
    g_texChar = Flag(@"yen") ? 0x00A5 : '\\';

    TSDocument *doc = [TSDocument new];
    SetUpColors(doc, Settings[@"fullwidth"] ?: @"both");
    doc.syntaxColor = YES; doc->fileIsTex = YES;
    doc.useExplColor = Flag(@"expl3");
    doc->indexColor = Flag(@"index");
    doc.fileIsXML = Flag(@"xml");
    doc.syntaxcolorEntry = Flag(@"entry");
    doc.blockCursor = Flag(@"blockCursor");
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:string
        attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:12]}];
    doc.textStorage = storage;
    doc->textView1 = MakeView(storage, size);
    doc->textView2 = MakeView(storage, size);
    doc.textView = doc->textView1;
    NSUInteger selection = MIN([Settings[@"selection"] unsignedIntegerValue], string.length);
    [doc->textView1 setSelectedRange:NSMakeRange(selection, 0)];
    [doc->textView2 setSelectedRange:NSMakeRange(selection, 0)];
    return doc;
}

static NSString *RunCase(NSDictionary *c)
{
    NSString *string = c[@"text"];
    // The source is tall enough to show all of a small sample, as the visible area is used for the active line.
    TSDocument *doc = MakeDocument(c[@"settings"], string, NSMakeSize(700, 100000));
    GoldenTextView *view = (GoldenTextView *)doc->textView1, *lower = (GoldenTextView *)doc->textView2;
    [view.layoutManager ensureLayoutForCharacterRange:NSMakeRange(0, string.length)];
    [lower.layoutManager ensureLayoutForCharacterRange:NSMakeRange(0, string.length)];
    Seed(view); Seed(lower);
    NSString *op = c[@"op"];
    NSArray *span = c[@"span"];
    if ([op isEqual:@"whole"]) {
        [doc colorizeText:view range:NSMakeRange(0, string.length)];
    } else if ([op isEqual:@"range"]) {
        [doc colorizeText:view range:NSMakeRange([span[0] unsignedIntegerValue], [span[1] unsignedIntegerValue])];
    } else if ([op isEqual:@"fix"]) {
        [doc fixColor:[span[0] unsignedIntegerValue] :[span[1] unsignedIntegerValue]];
        Check([TemporaryState(view) isEqual:TemporaryState(lower)], [NSString stringWithFormat:@"%@: both halves of a split window get the same colors", c[@"name"]]);
    } else if ([op isEqual:@"off"]) {
        [doc colorizeText:view range:NSMakeRange(0, string.length)];
        doc.syntaxColor = NO;
        [doc reColor:nil];
    }
    NSString *record = Record(view);
    if ([op isEqual:@"whole"]) {
        // Coloring again changes nothing, and the Experiment source, a view of its own text, gets the same colors.
        NSString *before = TemporaryState(view);
        [doc colorizeText:view range:NSMakeRange(0, string.length)];
        Check([before isEqual:TemporaryState(view)], [NSString stringWithFormat:@"%@: coloring again changes nothing", c[@"name"]]);
        NSTextStorage *scrapStorage = [[NSTextStorage alloc] initWithString:string attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:12]}];
        GoldenTextView *scrap = MakeView(scrapStorage, NSMakeSize(700, 100000));
        [scrap setSelectedRange:view.selectedRange];
        [scrap.layoutManager ensureLayoutForCharacterRange:NSMakeRange(0, string.length)];
        Seed(scrap);
        doc->scrapTextView = scrap;
        [doc colorizeText:scrap range:NSMakeRange(0, string.length)];
        Check([before isEqual:TemporaryState(scrap)], [NSString stringWithFormat:@"%@: the Experiment source gets the same colors", c[@"name"]]);
    }
    return record;
}

// The visible part of a long document is colored as the whole document would be, line by line.
static void CheckVisibleArea(NSString *string)
{
    TSDocument *doc = MakeDocument(@{@"expl3": @YES}, string, NSMakeSize(500, 300));
    GoldenTextView *whole = MakeView([[NSTextStorage alloc] initWithString:string attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:12]}], NSMakeSize(500, 300));
    [doc colorizeText:whole range:NSMakeRange(0, string.length)];
    NSTextView *view = doc->textView1;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 300) styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    window.contentView = view.enclosingScrollView;
    NSUInteger middle = string.length / 2;
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForCharacterRange:NSMakeRange(0, middle + 1)];
    NSRect line = [layout lineFragmentRectForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:middle] effectiveRange:NULL];
    [view sizeToFit];
    [view.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0, NSMinY(line))];
    [view.enclosingScrollView reflectScrolledClipView:view.enclosingScrollView.contentView];
    [doc colorizeVisibleAreaInTextView:view];
    NSRange glyphs = [layout glyphRangeForBoundingRect:view.enclosingScrollView.contentView.documentVisibleRect inTextContainer:view.textContainer];
    NSRange visible = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
    NSRange lines = [string lineRangeForRange:visible];
    if (getenv("TS_TRACE")) printf("visible %s lines %s of %lu\n", NSStringFromRange(visible).UTF8String, NSStringFromRange(lines).UTF8String, (unsigned long)string.length);
    Check(visible.length > 0 && visible.location > 0 && NSMaxRange(lines) < string.length, @"only a part in the middle of the long document is visible");
    BOOL same = YES, outsideUncolored = YES;
    for (NSUInteger i = 0; i < string.length; i++) {
        NSColor *color = [layout temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:i effectiveRange:NULL];
        if (NSLocationInRange(i, lines)) {
            NSColor *expected = [whole.layoutManager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:i effectiveRange:NULL];
            if (!(color == expected || [ColorName(color) isEqual:ColorName(expected)])) same = NO;
        } else if (color) outsideUncolored = NO;
    }
    Check(same, @"the visible lines get the colors of the whole document");
    Check(outsideUncolored, @"nothing outside the visible lines is colored");
}

static double Median(NSMutableArray<NSNumber *> *times)
{
    [times sortUsingSelector:@selector(compare:)];
    return times[times.count / 2].doubleValue * 1000;
}

static void Benchmark(NSString *string)
{
    TSDocument *doc = MakeDocument(@{@"expl3": @YES}, string, NSMakeSize(700, 600));
    NSTextView *view = doc->textView1;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 600) styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    window.contentView = view.enclosingScrollView;
    NSMutableArray *whole = [NSMutableArray array], *visible = [NSMutableArray array], *edit = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        NSDate *start = [NSDate date];
        [doc colorizeText:view range:NSMakeRange(0, string.length)];
        [whole addObject:@(-start.timeIntervalSinceNow)];
    }
    NSUInteger colored = 0;
    for (NSUInteger i = 0; i < string.length; ) {
        NSRange run;
        if ([view.layoutManager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:i effectiveRange:&run]) colored += run.length;
        i = NSMaxRange(run);
    }
    printf("colored %lu of %lu characters\n", (unsigned long)colored, (unsigned long)string.length);
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForCharacterRange:NSMakeRange(0, string.length)];
    [view sizeToFit];
    NSUInteger visibleCharacters = 0;
    for (int i = 0; i < 40; i++) {
        NSUInteger at = (string.length / 40) * i;
        NSRect line = [layout lineFragmentRectForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:at] effectiveRange:NULL];
        [view.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0, NSMinY(line))];
        [view.enclosingScrollView reflectScrolledClipView:view.enclosingScrollView.contentView];
        NSRange glyphs = [layout glyphRangeForBoundingRect:view.enclosingScrollView.contentView.documentVisibleRect inTextContainer:view.textContainer];
        visibleCharacters += [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL].length;
        NSDate *start = [NSDate date];
        [doc colorizeVisibleAreaInTextView:view];
        [visible addObject:@(-start.timeIntervalSinceNow)];
    }
    for (int i = 0; i < 400; i++) {
        NSUInteger at = (string.length / 400) * i;
        NSDate *start = [NSDate date];
        [doc fixColor:at :at + 1];
        [edit addObject:@(-start.timeIntervalSinceNow)];
    }
    printf("BENCHMARK %lu characters: whole %.1f ms, visible area (%lu characters) %.2f ms, one edit %.3f ms (medians)\n",
           (unsigned long)string.length, Median(whole), (unsigned long)(visibleCharacters / 40), Median(visible), Median(edit));
}

int main(int argc, const char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    LoadSpellLists();
    ColorNames = [NSMutableDictionary dictionary]; NamedColors = [NSMutableDictionary dictionary];
    Sentinel = NamedColor(@"PRE"); SentinelBackground = NamedColor(@"PRE-bg");
    [SUD setFloat:0.25 forKey:BlockCursorRKey]; [SUD setFloat:0.5 forKey:BlockCursorGKey]; [SUD setFloat:0.75 forKey:BlockCursorBKey];
    NSColor *cursor = [NSColor colorWithCalibratedRed:0.25 green:0.5 blue:0.75 alpha:1.0];
    ColorNames[[NSString stringWithFormat:@"%ld", lround([cursor colorUsingColorSpace:NSColorSpace.sRGBColorSpace].redComponent * 255)]] = @"BlockCursor";

    NSDictionary *input = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
    if (input[@"benchmark"]) {
        Benchmark(input[@"benchmark"]);
        return 0;
    }
    NSMutableDictionary *records = [NSMutableDictionary dictionary];
    for (NSDictionary *c in input[@"cases"]) {
        @try {
            records[c[@"name"]] = RunCase(c);
        } @catch (NSException *exception) {
            records[c[@"name"]] = [NSString stringWithFormat:@"exception %@: %@\n", exception.name, exception.reason];
        }
    }
    CheckVisibleArea(input[@"long"]);
    [[NSJSONSerialization dataWithJSONObject:records options:NSJSONWritingSortedKeys error:NULL] writeToFile:@(argv[2]) atomically:YES];
    return failures ? 1 : 0;
} }
'''

program = (PROGRAM.replace('@@DEFINES@@', defines).replace('@@SPELL_LISTS@@', spell_lists)
           .replace('@@XML_METHODS@@', xml_methods).replace('@@SYNTAX@@', strip_imports(text[SYNTAX])))

# The samples.
samples = {p.name: p.read_text(encoding='utf-8') for p in sorted(FIXTURES.iterdir()) if p.suffix in ('.tex', '.ptx')}
samples['latex-crlf.tex'] = samples['latex.tex'].replace('\n', '\r\n')
samples['latex-cr.tex'] = samples['latex.tex'].replace('\n', '\r')
samples['japanese-yen.tex'] = samples['japanese.tex'].replace('\\', '¥')
small = [name for name in samples if not name.startswith('real-')]
# A large document: every sample many times over, a few hundred kilobytes.
large = ''.join(samples[name] + '\n' for name in sorted(samples)) * 6
samples['large.tex'] = large

VARIANTS = {
    'plain': {},
    'expl3': {'expl3': True},
    'expl3-makeatletter': {'expl3': True, 'makeatletter': True},
    'makeatletter': {'makeatletter': True},
    'index-footnote': {'index': True, 'footnote': True},
    'index-footnote-expl3': {'index': True, 'footnote': True, 'expl3': True},
    'spelling': {'spellCommand': True, 'spellComment': True, 'spellParameter': True,
                 'userUnchecked': ['\\textbf'], 'userChecked': ['\\ref']},
    'spelling-exceptions': {'spellCommand': True, 'spellComment': True, 'spellParameter': True, 'exceptionsList': True,
                            'userUnchecked': ['\\textbf'], 'userChecked': ['\\ref']},
    'spelling-index-expl3': {'spellParameter': True, 'index': True, 'footnote': True, 'expl3': True},
    'spelling-texaware': {'spellCommand': True, 'spellComment': True, 'spellParameter': True, 'texAware': True, 'expl3': True},
    'fullwidth-foreground': {'fullwidth': 'foreground'},
    'fullwidth-none': {'fullwidth': 'none'},
    'entry': {'entry': True, 'selection': 30},
    'always-highlight': {'alwaysHighlight': True},
    'block-cursor-left': {'entry': True, 'blockCursor': True, 'blockSide': 0, 'blockWidth': 1, 'selection': 31},
    'block-cursor-center': {'entry': True, 'blockCursor': True, 'blockSide': 1, 'selection': 31},
    'block-cursor-right': {'entry': True, 'blockCursor': True, 'blockSide': 2, 'blockWidth': 1, 'selection': 31},
    'yen': {'yen': True},
    'yen-expl3': {'yen': True, 'expl3': True},
    'xml': {'xml': True},
    'right-justify': {'rightJustify': True},
    'right-justify-any': {'rightJustify': True, 'rightJustifyIfAny': True},
}
# Shown in full in the golden file; the other cases by their SHA-256.
DETAILED = {('latex.tex', 'plain'), ('latex.tex', 'index-footnote'), ('latex.tex', 'spelling'), ('latex.tex', 'makeatletter'),
            ('expl3.tex', 'expl3'), ('japanese.tex', 'plain'), ('japanese-yen.tex', 'yen'), ('broken.tex', 'plain'),
            ('broken.tex', 'index-footnote'), ('pretext.ptx', 'xml'), ('rtl.tex', 'right-justify'), ('latex.tex', 'entry'),
            ('latex.tex', 'block-cursor-center')}

cases = []
for sample in sorted(samples):
    if sample == 'large.tex':
        variants = ['plain', 'expl3', 'index-footnote-expl3', 'spelling-exceptions', 'xml']
    else:
        variants = list(VARIANTS)
    for variant in variants:
        cases.append({'name': f'{sample} {variant} whole', 'text': samples[sample], 'settings': VARIANTS[variant], 'op': 'whole'})
for sample in small:
    n = len(samples[sample])
    for variant in ('plain', 'expl3', 'index-footnote', 'xml'):
        # Edits in the middle: the coloring is extended to whole lines and one character further.
        for name, op, span in (('range', 'range', [n // 3, n // 10]), ('fix', 'fix', [n // 2, n // 2 + 3]),
                               ('fix-end', 'fix', [n - 1, n + 5]), ('fix-empty', 'fix', [n // 4, n // 4])):
            cases.append({'name': f'{sample} {variant} {name}', 'text': samples[sample], 'settings': VARIANTS[variant], 'op': op, 'span': span})
    cases.append({'name': f'{sample} plain off', 'text': samples[sample], 'settings': {}, 'op': 'off'})
names = [c['name'] for c in cases]
assert len(names) == len(set(names))


def run(payload):
    with tempfile.TemporaryDirectory(prefix='texshop-syntax-golden-') as tmp:
        tmp = Path(tmp)
        (tmp / 'probe.m').write_text(program, encoding='utf-8')
        (tmp / 'input.json').write_text(json.dumps(payload), encoding='utf-8')
        # Timed as a release build is optimized.
        optimization = ['-Os'] if 'benchmark' in payload else []
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', *optimization, '-framework', 'Cocoa', *include_args(ROOT), '-I', str(ROOT / 'Tests'),
                        str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], check=True)
        result = subprocess.run([str(tmp / 'probe'), str(tmp / 'input.json'), str(tmp / 'output.json')],
                                capture_output=True, text=True, timeout=600)
        output = json.loads((tmp / 'output.json').read_text(encoding='utf-8')) if (tmp / 'output.json').exists() else {}
        return result, output


if args.benchmark:
    manual = ROOT / 'DocumentSources/Manual Source/Manual.tex'
    for string in (large, manual.read_text(encoding='utf-8', errors='replace') * 3):
        result, _ = run({'benchmark': string})
        print(result.stdout, end='')
        if result.returncode:
            sys.exit(result.stderr)
    sys.exit(0)

started = time.time()
result, records = run({'cases': cases, 'long': large})
print(result.stdout, end='')
if result.returncode and not records:
    sys.exit('FAIL: ' + result.stderr)


def digest(record):
    return hashlib.sha256(record.encode('utf-8')).hexdigest()


lines = [f'# Syntax coloring golden record: {len(cases)} cases. Rewrite with run-syntax-coloring-golden.py --update.']
for c in cases:
    record = records.get(c['name'], 'missing\n')
    sample, variant, op = c['name'].split(' ')
    if (sample, variant) in DETAILED and op == 'whole':
        lines.append(f'== {c["name"]}')
        lines.extend(record.rstrip('\n').split('\n') if record.strip() else [])
    lines.append(f'sha256 {c["name"]} {digest(record)}')
golden_text = '\n'.join(lines) + '\n'

if args.dump_all:
    Path(args.dump_all).write_text(''.join(f'== {c["name"]}\n{records.get(c["name"], "missing")}' for c in cases), encoding='utf-8')
    print(f'Wrote the record of {len(cases)} cases to {args.dump_all}')
    sys.exit(1 if result.returncode else 0)
if args.update:
    GOLDEN.write_text(golden_text, encoding='utf-8')
    print(f'Wrote {GOLDEN.relative_to(ROOT)} ({len(cases)} cases)')
    sys.exit(1 if result.returncode else 0)

expected = GOLDEN.read_text(encoding='utf-8')
if golden_text != expected:
    expected_hashes = {l[7:].rsplit(' ', 1)[0]: l.rsplit(' ', 1)[1] for l in expected.splitlines() if l.startswith('sha256 ')}
    changed = [c['name'] for c in cases if expected_hashes.get(c['name']) != digest(records.get(c['name'], 'missing\n'))]
    for name in changed[:10]:
        print(f'FAIL: the colors changed in {name}')
    if len(changed) > 10:
        print(f'FAIL: ... and {len(changed) - 10} more cases')
    if not changed:
        print('FAIL: the golden file differs from the current record')
    if args.mutation:
        print(f'PASS: detected mutation {args.mutation}')
        sys.exit(0)
    sys.exit('FAIL: compare the full records of two revisions with --dump-all')
if args.mutation:
    if result.returncode:
        print(f'PASS: detected mutation {args.mutation}')
        sys.exit(0)
    sys.exit(f'FAIL: mutation {args.mutation} was not detected')
if result.returncode:
    sys.exit('FAIL: ' + result.stderr)
print(f'PASS: syntax coloring is unchanged in {len(cases)} cases ({time.time() - started:.0f} s)')
