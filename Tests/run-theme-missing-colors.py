#!/usr/bin/env python3
"""A theme that has lost its colors (its file emptied or edited elsewhere) still shows readable text.

The color readers of TSColorSupport are compiled verbatim. For an empty theme, in the light and in the dark mode:
the text and background of the source, the console and the log differ enough to read (contrast 4.5 or more); the
document's source, console and log views get these colors from the production part of
-[TSDocument changeColorsUsingDictionary:] (real NSTextViews), the Experiment console from the production
-[TSExperimentConsoleController updateConsoleColors:], and the Settings wells (-colorForKey:fromDictionary:) show
the same colors. Nothing is written into the theme, and nothing is shown on screen. --mutations removes each part
and the test must then fail."""
from pathlib import Path
import subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
support = (root / 'Sources/Editor/TSColorSupport.m').read_text(encoding='utf-8')
signatures = ['- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *) colorAndAlphaFromDictionary:',
              '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:',
              '- (NSColor *)colorForKey: (NSString *)theKey fromDictionary:', '- (NSColor *)opaqueColorForKey: (NSString *)theKey fromDictionary:']
readers = [method(support, s) for s in signatures]
document_source = (root / 'Sources/Editor/TSDocument-Color.m').read_text(encoding='utf-8')
start = document_source.index('    myBackgroundColor = [[TSColorSupport sharedInstance] ')
end = document_source.index('    [outputText setBackgroundColor: myBackgroundColor];\n') + len('    [outputText setBackgroundColor: myBackgroundColor];\n')
document = document_source[start:end]
console_source = (root / 'Sources/Typesetting/TSExperimentConsoleController.m').read_text(encoding='utf-8')
console = method(console_source, '- (void)updateConsoleColors:(NSNotification *)notification\n{')
fragments = [('complete method:' + s, support, m) for s, m in zip(signatures, readers)]
fragments += [('statement span:document views', document_source, document), ('complete method:updateConsoleColors', console_source, console)]

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSThemeAlpha.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %s %d: %s\n", mode, __LINE__, #__VA_ARGS__); exit(1); } } while (0)
static const char *mode = "";
NSDictionary *liteColors, *darkColors;
@interface TSColorSupport : NSObject
- (NSColor *)opaqueColorForKey:(NSString *)theKey fromDictionary:(NSDictionary *)theDictionary isWindowDark:(BOOL)mode;
- (NSColor *)colorForKey:(NSString *)theKey fromDictionary:(NSDictionary *)theDictionary isWindowDark:(BOOL)mode;
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
__READERS__
@end
// The source, log and console views of a document, with the production statements that color them.
@interface Document : NSObject {
@public
    NSTextView *textView1, *textView2, *outputText;
}
@property NSTextView *logTextView;
@end
@implementation Document
- (void)applyDictionary:(NSDictionary *)colorDictionary dark:(BOOL)withDarkColors
{
    NSColor *myBackgroundColor, *myTextColor;
__DOCUMENT__
}
@end
// The Experiment console with its production -updateConsoleColors:.
@interface TSExperimentConsoleController : NSObject
@property NSWindow *window;
@property NSTextView *outputText;
@property NSColor *themeTextColor;
@end
@implementation TSExperimentConsoleController
__CONSOLE__
@end

static double Channel(double c) { return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static double Luminance(NSColor *color)
{
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return 0.2126 * Channel(rgb.redComponent) + 0.7152 * Channel(rgb.greenComponent) + 0.0722 * Channel(rgb.blueComponent);
}
static double Contrast(NSColor *a, NSColor *b)
{
    if (a == nil || b == nil) return 0;
    double x = Luminance(a), y = Luminance(b);
    return (MAX(x, y) + 0.05) / (MIN(x, y) + 0.05);
}
static BOOL SameRGB(NSColor *a, NSColor *b)
{
    NSColor *x = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *y = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return x && y && fabs(x.redComponent - y.redComponent) < 1e-6 && fabs(x.greenComponent - y.greenComponent) < 1e-6 && fabs(x.blueComponent - y.blueComponent) < 1e-6;
}
static NSTextView *View(void) { NSTextView *v = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)]; v.string = @"TeX console 123"; return v; }

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    TSColorSupport *colors = [TSColorSupport sharedInstance];
    NSArray *pairs = @[@[@"EditorText", @"EditorBackground"], @[@"ConsoleText", @"ConsoleBackground"], @[@"LogText", @"LogBackground"],
                       @[@"EditorInsertionPoint", @"EditorBackground"]];
    // An empty theme, one with only the text color, and one whose colors are not colors.
    NSArray *themes = @[@{}, @{@"EditorText": @[@0.5, @0.3, @0.2, @1], @"Title": @"Mine"}, @{@"ConsoleText": @[], @"ConsoleBackground": @3, @"LogBackground": @[@"x", @"y", @"z"]}];
    for (int dark = 0; dark <= 1; dark++) {
        mode = dark ? "dark" : "light";
        for (NSDictionary *theme in themes) {
            NSDictionary *before = [theme copy];
            for (NSArray *pair in pairs) {
                NSString *textKey = pair[0], *backgroundKey = pair[1];
                if (theme[textKey] && [theme[textKey] isKindOfClass:NSArray.class] && [theme[textKey] count] >= 3) continue;
                NSColor *text = [colors opaqueColorForKey:textKey fromDictionary:theme isWindowDark:dark];
                NSColor *background = [colors opaqueColorForKey:backgroundKey fromDictionary:theme isWindowDark:dark];
                REQUIRE(Contrast(text, background) >= 4.5);
                // The Settings wells show the same colors.
                REQUIRE(SameRGB([colors colorForKey:textKey fromDictionary:theme isWindowDark:dark], text));
                REQUIRE(SameRGB([colors colorForKey:backgroundKey fromDictionary:theme isWindowDark:dark], background));
            }
            // The document's views.
            Document *document = [Document new];
            document->textView1 = View(); document->textView2 = View(); document->outputText = View(); document.logTextView = View();
            [document applyDictionary:theme dark:dark];
            NSMutableArray *views = [NSMutableArray arrayWithObjects:document->outputText, document.logTextView, nil];
            if (theme[@"EditorText"] == nil) [views addObjectsFromArray:@[document->textView1, document->textView2]];
            for (NSTextView *view in views)
                REQUIRE(Contrast(view.textColor, view.backgroundColor) >= 4.5);
            // The Experiment console.
            TSExperimentConsoleController *console = [TSExperimentConsoleController new];
            console.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
            console.window.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            console.outputText = View();
            [console updateConsoleColors:[NSNotification notificationWithName:@"colors" object:nil userInfo:theme.count ? theme : @{@"Title": @"Empty"}]];
            REQUIRE(Contrast(console.outputText.textColor, console.outputText.backgroundColor) >= 4.5);
            REQUIRE([theme isEqual:before]);
        }
        printf("PASS: %s: a theme without its colors shows readable text in the source, the console, the log and the Experiment console, and the wells show the same colors\n", mode);
    }
} return 0; }
'''


def run(parts, label):
    program = PROGRAM.replace('__READERS__', '\n'.join(parts['readers'])).replace('__DOCUMENT__', parts['document']).replace('__CONSOLE__', parts['console'])
    with tempfile.TemporaryDirectory(prefix='texshop-theme-missing-colors-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(folder / 'test.m'), '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        return subprocess.run([str(folder / 'test')], capture_output=True, text=True, timeout=60)


parts = {'readers': readers, 'document': document, 'console': console}
result = run(parts, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: a theme without its colors shows text that cannot be read')
if '--mutations' in sys.argv:
    mutations = {
        'no built-in light colors': ('readers', '    if (builtIn != nil)\n        return', '    if (NO)\n        return', 0),
        'no built-in dark colors': ('readers', '    if (builtIn != nil)\n        return', '    if (NO)\n        return', 1),
        'the document takes no color': ('document', '[[TSColorSupport sharedInstance] opaqueColorForKey: @"ConsoleText" fromDictionary: colorDictionary isWindowDark: withDarkColors]',
                                        '[[TSColorSupport sharedInstance] colorFromDictionary:colorDictionary andKey: @"ConsoleText"]', None),
    }
    for name, (where, before, after, which) in mutations.items():
        changed = dict(parts)
        if where == 'readers':
            readers2 = list(parts['readers'])
            index = [i for i, m in enumerate(readers2) if before in m][which]
            readers2[index] = readers2[index].replace(before, after)
            changed['readers'] = readers2
        else:
            assert changed[where].count(before) == 1, name
            changed[where] = changed[where].replace(before, after)
        r = run(changed, name)
        assert r.returncode and 'FAIL' in r.stderr, (name, r.stdout, r.stderr)
        print('DETECTED', name, r.stderr.strip().splitlines()[-1])
print('PASS: themes without their colors stay readable, in documents, the Experiment console and the Settings wells')
