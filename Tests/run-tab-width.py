#!/usr/bin/env python3
"""A tab in the source is as wide as the number of spaces set in Settings > Editor, in any font.

The production -[TSDocument fixUpTabs] (when a document opens and when the font or the tab
size changes in Settings) with its tabStopArrayForFontAndTabWidth, and -[TSTextView fixupTabs]
(after a font change from the Font panel), are compiled unchanged onto a small document
stand-in whose two source views show one text, as a split source does. The views are never
put in a window. In proportional and monospaced fonts, the text after a tab must start where
the text after the same number of spaces starts, also after more than a hundred tabs and
after a tab far along a long line; after a font change in one half of the source, the other
half must take the same paragraph style, which the Experiment source copies from the half in
use. Preferences stay in memory."""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile
from source_tree import include_args, source_file

DOCUMENT = 'Sources/Document/TSDocument.m'
TEXT_VIEW = 'Sources/Editor/TSTextView.m'

MUTATIONS = {
    # The width of glyph number 32, which is not the space in most proportional fonts.
    'text-view-glyph-32': (TEXT_VIEW,
        '    CGFloat charWidth = font ? [@" " sizeWithAttributes:@{NSFontAttributeName: font}].width : 0;\n',
        '    CGFloat charWidth = [font advancementForGlyph:(NSGlyph)\' \'].width;\n'),
    'document-glyph-32': (DOCUMENT,
        '\tcharWidth = font ? [@" " sizeWithAttributes:@{NSFontAttributeName: font}].width : 0;\n',
        '\tcharWidth = [font advancementForGlyph:(NSGlyph)\' \'].width;\n'),
    'document-widest-glyph': (DOCUMENT,
        '\tcharWidth = font ? [@" " sizeWithAttributes:@{NSFontAttributeName: font}].width : 0;\n',
        '\tcharWidth = [font maximumAdvancement].width;\n'),
    # The tabs are measured in a saved font that the source does not take.
    'tabs-in-refused-font': (DOCUMENT,
        '    font = [textView1 font] ?: font;\n', ''),
    # Only the hundred tab stops, nothing after them.
    'no-interval-after-stops': (DOCUMENT,
        '\tnewStyle.defaultTabInterval = [(NSTextTab *)desiredTabStops.firstObject location];\n', ''),
    # The other half of the source keeps its old paragraph style.
    'other-half-keeps-style': (TEXT_VIEW,
        '        other.defaultParagraphStyle = paragraphStyle;\n', ''),
    'other-half-keeps-typing-style': (TEXT_VIEW,
        '        otherTypingAttributes[NSParagraphStyleAttributeName] = paragraphStyle;\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = {path: (root / path).read_text(encoding='latin1') for path in (DOCUMENT, TEXT_VIEW)}
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert text[path].count(old) == 1, args.mutation
    text[path] = text[path].replace(old, new)


def method(source, signature):
    """A method or function from its signature to the closing brace at the start of a line."""
    start = source.index('\n' + signature) + 1
    end = re.compile(r'\n ?\}\n').search(source, start)
    return source[start:end.end()]


globals_m = source_file(root, 'globals.m').read_text(encoding='latin1')
keys = dict(re.findall(r'^NSString \*(\w+Key)\s*=\s*(@"[^"]*");', globals_m, re.M))
defines = '\n'.join(f'#define {k} {v}' for k, v in sorted(keys.items()))

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSSourceFormatRanges.h"
#define SUD TSIsolatedAppKitDefaults
@@DEFINES@@
static int failures;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }

@interface NSText (Extras)
- (void)setFontSafely:(NSFont *)aFont;
@end

@class TSDocument;
@interface TSTextView : NSTextView
@property (weak) TSDocument *document;
- (void)fixupTabs;
@end

@interface TSDocument : NSObject {
@public
    NSTextView *textView, *textView1, *textView2;
    NSTextStorage *_textStorage;
}
- (NSTextView *)textView1;
- (NSTextView *)textView2;
- (void)applyExperimentTextLayout;
- (void)fixUpTabs;
@end

@implementation TSTextView
@@TEXT_VIEW_TABS@@
@end

@@TAB_STOPS@@

@implementation TSDocument
- (NSTextView *)textView1 { return textView1; }
- (NSTextView *)textView2 { return textView2; }
- (void)applyExperimentTextLayout {}
@@FIX_UP_TABS@@
@end

// A document whose two source views show one text, as a split source does; neither is in a window.
static TSDocument *MakeDocument(void)
{
    TSDocument *document = [TSDocument new];
    document->_textStorage = [NSTextStorage new];
    NSMutableArray<TSTextView *> *views = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        NSLayoutManager *layout = [NSLayoutManager new];
        NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(100000, 1.0e7)];
        [layout addTextContainer:container];
        [document->_textStorage addLayoutManager:layout];
        TSTextView *view = [[TSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100000, 1000) textContainer:container];
        view.horizontallyResizable = YES;
        view.document = document;
        [views addObject:view];
    }
    document->textView = document->textView1 = views[0];
    document->textView2 = views[1];
    return document;
}

static NSString *Repeat(NSString *string, NSInteger count)
{
    return [@"" stringByPaddingToLength:string.length * count withString:string startingAtIndex:0];
}

// Lines: a tab, then as many spaces as the tab size; 101 tabs, then as many spaces; a long run
// of W reaching past the hundredth tab stop, then a tab. Each line ends in "x".
static NSString *Sample(NSInteger spaces, NSInteger wCount)
{
    return [NSString stringWithFormat:@"\tx\n%@x\n%@x\n%@x\n%@\tx\n", Repeat(@" ", spaces), Repeat(@"\t", 101),
            Repeat(@" ", spaces * 101), Repeat(@"W", wCount)];
}

static void CheckLayout(NSTextView *view, NSInteger spaces, NSString *path, NSString *label)
{
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForTextContainer:view.textContainer];
    NSString *string = view.string;
    NSMutableArray<NSNumber *> *xs = [NSMutableArray array], *ys = [NSMutableArray array];
    NSMutableArray<NSNumber *> *lineYs = [NSMutableArray array];
    [string enumerateSubstringsInRange:NSMakeRange(0, string.length) options:NSStringEnumerationByLines
                            usingBlock:^(NSString *line, NSRange range, NSRange enclosing, BOOL *stop) {
        NSUInteger x = NSMaxRange(range) - 1;
        NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:x];
        NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
        NSRect first = [layout lineFragmentRectForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:range.location] effectiveRange:NULL];
        [xs addObject:@([layout locationForGlyphAtIndex:glyph].x)];
        [ys addObject:@(NSMinY(fragment))];
        [lineYs addObject:@(NSMinY(first))];
    }];
    CGFloat padding = view.textContainer.lineFragmentPadding;
    CGFloat interval = xs[1].doubleValue - padding;
    Check(fabs(xs[0].doubleValue - xs[1].doubleValue) < 0.01, [NSString stringWithFormat:
          @"%@: a tab is %.3f wide and %ld spaces %.3f (%@)", path, xs[0].doubleValue - padding, (long)spaces, interval, label]);
    Check(fabs(xs[2].doubleValue - xs[3].doubleValue) < 0.01 && [ys[2] isEqual:lineYs[2]], [NSString stringWithFormat:
          @"%@: 101 tabs end at %.3f and %ld spaces at %.3f (%@)", path, xs[2].doubleValue - padding, (long)spaces * 101,
          xs[3].doubleValue - padding, label]);
    CGFloat afterLong = xs[4].doubleValue - padding;
    CGFloat steps = afterLong / interval;
    Check([ys[4] isEqual:lineYs[4]] && afterLong > 100 * interval && fabs(steps - round(steps)) < 0.01, [NSString stringWithFormat:
          @"%@: a tab after a long line goes to %.3f on line y %.1f (line starts at y %.1f, interval %.3f) (%@)", path,
          afterLong, ys[4].doubleValue, lineYs[4].doubleValue, interval, label]);
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    NSMutableArray<NSFont *> *fonts = [NSMutableArray array];
    for (NSString *name in @[@"Helvetica", @"HiraginoSans-W3", @"Osaka", @"TimesNewRomanPSMT", @"Avenir-Book",
                             @"Menlo-Regular", @"CourierNewPSMT", @"Osaka-Mono"]) {
        // A document takes only a font of the Font panel (-[NSText setFontSafely:]).
        NSFont *font = [NSFont fontWithName:name size:13];
        if (font && [NSFontManager.sharedFontManager.availableFonts containsObject:name]) [fonts addObject:font];
        else printf("note: %s is not installed\n", name.UTF8String);
    }
    Check([fonts.firstObject.fontName isEqual:@"Helvetica"], @"Helvetica is installed");
    [fonts addObject:[NSFont userFontOfSize:12]];
    [fonts addObject:[NSFont userFixedPitchFontOfSize:12]];
    NSFont *startFont = [NSFont fontWithName:@"Menlo-Regular" size:14] ?: [NSFont userFixedPitchFontOfSize:14];
    [SUD setBool:YES forKey:SaveDocumentFontKey];

    for (NSFont *font in fonts)
        for (NSNumber *count in @[@2, @4, @8]) {
            NSInteger spaces = count.integerValue;
            [SUD setInteger:spaces forKey:tabsKey];
            NSString *label = [NSString stringWithFormat:@"%@ %.0fpt, %ld spaces", font.fontName, font.pointSize, (long)spaces];
            CGFloat wWidth = [@"W" sizeWithAttributes:@{NSFontAttributeName: font}].width;
            CGFloat spaceWidth = [@" " sizeWithAttributes:@{NSFontAttributeName: font}].width;
            NSInteger wCount = (NSInteger)ceil(100 * spaces * spaceWidth / wWidth) + 3;

            // A document opened with this font in Settings.
            [SUD setObject:[NSArchiver archivedDataWithRootObject:font] forKey:DocumentFontKey];
            TSDocument *opened = MakeDocument();
            [opened->_textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:Sample(spaces, wCount)];
            [opened fixUpTabs];
            CheckLayout(opened->textView1, spaces, @"opened document", label);

            // A document opened in another font; this font is then chosen in one half of the split source,
            // as -[TSTextView changeFont:] gives it to both halves and fixes the tabs of its own.
            for (int half = 0; half < 2; half++) {
                [SUD setObject:[NSArchiver archivedDataWithRootObject:startFont] forKey:DocumentFontKey];
                TSDocument *changed = MakeDocument();
                [changed->_textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:Sample(spaces, wCount)];
                [changed fixUpTabs];
                TSTextView *chosen = (TSTextView *)(half ? changed->textView2 : changed->textView1);
                NSTextView *other = half ? changed->textView1 : changed->textView2;
                changed->textView1.font = font;
                changed->textView2.font = font;
                [chosen fixupTabs];
                NSString *path = half ? @"font chosen in the lower half" : @"font chosen in the upper half";
                CheckLayout(chosen, spaces, path, label);
                Check([other.defaultParagraphStyle isEqual:chosen.defaultParagraphStyle], [NSString stringWithFormat:
                      @"%@: the other half takes the same paragraph style (%@)", path, label]);
                Check([other.typingAttributes[NSParagraphStyleAttributeName] isEqual:chosen.defaultParagraphStyle] &&
                      [other.typingAttributes[NSFontAttributeName] isEqual:font], [NSString stringWithFormat:
                      @"%@: text typed in the other half takes the same style and font (%@)", path, label]);
                // What the other half shows and what is typed there lays out as in the chosen half.
                [other insertText:@"\ty\n" replacementRange:NSMakeRange(0, 0)];
                NSLayoutManager *layout = other.layoutManager;
                [layout ensureLayoutForTextContainer:other.textContainer];
                CGFloat afterTypedTab = [layout locationForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:1]].x;
                CGFloat afterTab = [layout locationForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:4]].x;
                Check(fabs(afterTypedTab - afterTab) < 0.01, [NSString stringWithFormat:
                      @"%@: a tab typed in the other half is %.3f wide, the others %.3f (%@)", path, afterTypedTab, afterTab, label]);
            }
        }

    // A font saved by an older version that is no longer among the fonts of the Font panel, though it can
    // still be read: the source keeps its font (-setFontSafely:), and the tabs follow the font it keeps.
    NSInteger refusedFonts = 0;
    for (NSString *name in @[@"Courier", @"Times-Roman"]) {
        NSFont *saved = [NSFont fontWithName:name size:12];
        if (!saved || [NSFontManager.sharedFontManager.availableFonts containsObject:name]) {
            printf("note: %s is not a saved font that the source refuses here\n", name.UTF8String);
            continue;
        }
        refusedFonts++;
        for (NSNumber *count in @[@2, @4, @8]) {
            NSInteger spaces = count.integerValue;
            [SUD setInteger:spaces forKey:tabsKey];
            [SUD setObject:[NSArchiver archivedDataWithRootObject:saved] forKey:DocumentFontKey];
            TSDocument *opened = MakeDocument();
            NSFont *shown = opened->textView1.font;
            CGFloat wWidth = [@"W" sizeWithAttributes:@{NSFontAttributeName: shown}].width;
            CGFloat spaceWidth = [@" " sizeWithAttributes:@{NSFontAttributeName: shown}].width;
            [opened->_textStorage replaceCharactersInRange:NSMakeRange(0, 0)
                withString:Sample(spaces, (NSInteger)ceil(100 * spaces * spaceWidth / wWidth) + 3)];
            [opened fixUpTabs];
            NSString *label = [NSString stringWithFormat:@"saved %@, shown %@ %.0fpt, %ld spaces", name, opened->textView1.font.fontName,
                               opened->textView1.font.pointSize, (long)spaces];
            Check([opened->textView1.font.fontName isEqual:shown.fontName] && opened->textView1.font.pointSize == shown.pointSize, [@"the source keeps its font: " stringByAppendingString:label]);
            CheckLayout(opened->textView1, spaces, @"opened document with a saved font the source does not take", label);
        }
    }

    // A font that could not be read gives the tab stops and raises nothing.
    @try {
        NSArray *stops = tabStopArrayForFontAndTabWidth(nil, 4);
        Check(stops.count == 100, @"an unreadable font still gives the tab stops");
    } @catch (NSException *exception) {
        Check(NO, [@"an unreadable font raises " stringByAppendingString:exception.reason ?: @""]);
    }

    if (failures) return 1;
    printf("PASS: a tab is as wide as the set number of spaces in %lu fonts, in an opened document and after a font change "
           "in either half of the source, also after 101 tabs and far along a long line, and with %ld saved fonts the source does not take\n",
           (unsigned long)fonts.count, (long)refusedFonts);
} return 0; }
'''
replacements = {
    'DEFINES': defines,
    'TEXT_VIEW_TABS': method(text[TEXT_VIEW], '- (void)fixupTabs'),
    'TAB_STOPS': method(text[DOCUMENT], 'static NSArray *tabStopArrayForFontAndTabWidth('),
    'FIX_UP_TABS': method(text[DOCUMENT], '- (void)fixUpTabs {'),
}
for name, value in replacements.items():
    program = program.replace(f'@@{name}@@', value)

with tempfile.TemporaryDirectory(prefix='texshop-tab-width-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(source_file(root, 'NSText-Extras.m')),
                    '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=300)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
