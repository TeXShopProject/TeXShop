#!/usr/bin/env python3
"""A tab in the source is as wide as the number of spaces set in Settings > Editor, in any font.

The tab stops that the document sets when it opens (tabStopArrayForFontAndTabWidth in
TSDocument.m) and the tab interval that the source sets after a font change (-[TSTextView
fixupTabs]) are compiled unchanged. Text views that are never put in a window lay out a tab
and the same number of spaces in proportional and monospaced fonts, and the text after
them must start at the same place. Preferences stay in memory."""
from pathlib import Path
import argparse, re, subprocess, sys, tempfile
from source_tree import include_args

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


program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSSourceFormatRanges.h"
#define SUD TSIsolatedAppKitDefaults
static NSString *tabsKey = @"tabs";
static int failures;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }

@interface TSTextView : NSTextView
- (void)fixupTabs;
@end
@implementation TSTextView
@@TEXT_VIEW_TABS@@
@end

@@TAB_STOPS@@

// Where the "x" after the tab and the "x" after the spaces start; the text view is in no window.
static void Positions(NSTextView *view, CGFloat *afterTab, CGFloat *afterSpaces)
{
    NSLayoutManager *layout = view.layoutManager;
    [layout ensureLayoutForTextContainer:view.textContainer];
    NSString *string = view.string;
    NSUInteger first = [string rangeOfString:@"x"].location;
    NSUInteger second = [string rangeOfString:@"x" options:NSBackwardsSearch].location;
    *afterTab = [layout locationForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:first]].x;
    *afterSpaces = [layout locationForGlyphAtIndex:[layout glyphIndexForCharacterAtIndex:second]].x;
}

static NSString *Sample(NSInteger spaces)
{
    return [NSString stringWithFormat:@"\tx\n%@x\n", [@"" stringByPaddingToLength:spaces withString:@" " startingAtIndex:0]];
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    NSMutableArray<NSFont *> *fonts = [NSMutableArray array];
    for (NSString *name in @[@"Helvetica", @"HiraginoSans-W3", @"Osaka", @"Times-Roman", @"Avenir-Book",
                             @"Menlo-Regular", @"Courier", @"Osaka-Mono"]) {
        NSFont *font = [NSFont fontWithName:name size:13];
        if (font) [fonts addObject:font];
        else printf("note: %s is not installed\n", name.UTF8String);
    }
    Check([fonts.firstObject.fontName isEqual:@"Helvetica"], @"Helvetica is installed");
    [fonts addObject:[NSFont userFontOfSize:12]];
    [fonts addObject:[NSFont userFixedPitchFontOfSize:12]];

    for (NSFont *font in fonts)
        for (NSNumber *count in @[@2, @4, @8]) {
            NSInteger spaces = count.integerValue;
            [SUD setInteger:spaces forKey:tabsKey];
            NSString *label = [NSString stringWithFormat:@"%@ %.0fpt, %ld spaces", font.fontName, font.pointSize, (long)spaces];
            CGFloat afterTab, afterSpaces;

            // As the source after a font change.
            TSTextView *view = [[TSTextView alloc] initWithFrame:NSMakeRect(0, 0, 2000, 200)];
            view.font = font;
            view.string = Sample(spaces);
            [view fixupTabs];
            Positions(view, &afterTab, &afterSpaces);
            Check(fabs(afterTab - afterSpaces) < 0.01, [NSString stringWithFormat:
                  @"after a font change, a tab is %.3f wide and %ld spaces %.3f (%@)", afterTab, (long)spaces, afterSpaces, label]);

            // As the document sets it when it opens.
            NSMutableParagraphStyle *style = [NSParagraphStyle.defaultParagraphStyle mutableCopy];
            style.tabStops = tabStopArrayForFontAndTabWidth(font, spaces);
            NSTextView *opened = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 2000, 200)];
            [opened.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:Sample(spaces)
                attributes:@{NSFontAttributeName: font, NSParagraphStyleAttributeName: style}]];
            Positions(opened, &afterTab, &afterSpaces);
            Check(fabs(afterTab - afterSpaces) < 0.01, [NSString stringWithFormat:
                  @"in an opened document, a tab is %.3f wide and %ld spaces %.3f (%@)", afterTab, (long)spaces, afterSpaces, label]);
        }

    // A font that could not be read gives no tab stops of width zero and raises nothing.
    @try {
        NSArray *stops = tabStopArrayForFontAndTabWidth(nil, 4);
        Check(stops.count == 100, @"an unreadable font still gives the tab stops");
    } @catch (NSException *exception) {
        Check(NO, [@"an unreadable font raises " stringByAppendingString:exception.reason ?: @""]);
    }

    if (failures) return 1;
    printf("PASS: a tab is as wide as the set number of spaces in %lu fonts, after a font change and in an opened document\n",
           (unsigned long)fonts.count);
} return 0; }
'''
program = program.replace('@@TEXT_VIEW_TABS@@', method(text[TEXT_VIEW], '- (void)fixupTabs'))
program = program.replace('@@TAB_STOPS@@', method(text[DOCUMENT], 'static NSArray *tabStopArrayForFontAndTabWidth('))

with tempfile.TemporaryDirectory(prefix='texshop-tab-width-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'),
                    '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=120)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
