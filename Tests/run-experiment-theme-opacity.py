#!/usr/bin/env python3
"""The Experiment source, console and preview draw their theme colors opaque, as the
document's source, console and preview do.

Several themes store an opacity of 0 with the editor and console backgrounds, for
example SolarizedDark, SolarizedLite and Old. The document's windows ignore it; the
Experiment windows used it, so their backgrounds were transparent and showed the
window behind the text, nearly black in Dark Mode.

The production color methods of TSColorSupport and the production theme methods of
ScrapTextView, TSExperimentConsoleController and ScrapPDFKitView are compiled onto small
stand-ins and given every bundled theme, in Light and Dark Mode, at opening and as a
live theme edit. Each color must equal the one the document uses, with opacity 1.
Windows are never ordered on screen."""
from pathlib import Path
import argparse, os, re, subprocess, sys, tempfile
from source_tree import include_args

SUPPORT = 'Sources/Editor/TSColorSupport.m'
SOURCE = 'Sources/Editor/ScrapTextView.m'
CONSOLE = 'Sources/Typesetting/TSExperimentConsoleController.m'
PREVIEW = 'Sources/Preview/ScrapPDFKitView.m'

MUTATIONS = {
    'source-background': (SOURCE, 'opaqueColorForKey:@"EditorBackground"', 'colorForKey:@"EditorBackground"'),
    'source-text': (SOURCE, 'opaqueColorForKey:@"EditorText"', 'colorForKey:@"EditorText"'),
    'console-background': (CONSOLE, 'opaqueColorForKey:@"ConsoleBackground"', 'colorForKey:@"ConsoleBackground"'),
    'preview-background': (PREVIEW, 'opaqueColorForKey:@"PreviewBackground"', 'colorForKey:@"PreviewBackground"'),
    'opaque-keeps-alpha': (SUPPORT, '    NSColor *theColor = [self colorFromDictionary: theDictionary andKey: theKey];\n    if (theColor != nil)',
                           '    NSColor *theColor = [self colorAndAlphaFromDictionary: theDictionary andKey: theKey];\n    if (theColor != nil)'),
    'no-built-in-color': (SUPPORT, '    if (theColor != nil)\n        return theColor;\n    if (mode)\n        return [self darkColorWithKey: theKey];',
                          '    if (theColor != nil)\n        return theColor;\n    if (mode)\n        return nil;'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = {path: (root / path).read_text(encoding='latin-1') for path in (SUPPORT, SOURCE, CONSOLE, PREVIEW)}
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert text[path].count(old) == 1, args.mutation
    text[path] = text[path].replace(old, new)


def method(source, signature):
    """The implementation of the method, not a declaration ending in a semicolon."""
    start = re.compile(re.escape(signature) + r'[^;{]*\{').search(source).start()
    return source[start:source.index('\n}\n', start) + 3]


support = '\n'.join(method(text[SUPPORT], s) for s in [
    '- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *) colorAndAlphaFromDictionary:',
    '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:',
    '- (NSColor *)colorForKey: (NSString *)theKey fromDictionary:', '- (NSColor *)opaqueColorForKey:'])
source = method(text[SOURCE], '- (void)updateExperimentColors:')
console = method(text[CONSOLE], '- (void)updateConsoleColors:')
preview = method(text[PREVIEW], '- (void)updateExperimentColors:')

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSColorSupport.h"
#import "TSExperimentTheme.h"
NSDictionary *liteColors, *darkColors;
@implementation TSColorSupport
+ (id)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
@@SUPPORT@@
@end
@interface SourceFixture : NSTextView
@end
@implementation SourceFixture
@@SOURCE@@
@end
@interface ConsoleFixture : NSObject
@property (strong) NSWindow *window;
@property (strong) NSTextView *outputText;
@end
@implementation ConsoleFixture
@@CONSOLE@@
@end
@interface PreviewFixture : NSView
@property BOOL experimentViewReady;
@property (strong) NSColor *themePaperColor;
@end
@implementation PreviewFixture
- (void)updateExperimentPaper {}
@@PREVIEW@@
@end

static int failures, checks;
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) { printf("FAIL: %s\n", what.UTF8String); failures++; } }
static NSWindow *Window(NSView *view) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled
        backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO; w.contentView = view;
    return w;
}
// The color the document's own windows use for key (TSDocument-Color.m), or the
// built-in color for a theme without it.
static NSColor *DocumentColor(NSDictionary *theme, NSString *key, BOOL dark) {
    TSColorSupport *colors = [TSColorSupport sharedInstance];
    return [colors colorFromDictionary:theme andKey:key] ?: (dark ? [colors darkColorWithKey:key] : [colors liteColorWithKey:key]);
}
static BOOL Same(NSColor *a, NSColor *b) {
    if (!a || !b) return a == b;
    a = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; b = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return fabs(a.redComponent - b.redComponent) < 1e-6 && fabs(a.greenComponent - b.greenComponent) < 1e-6 &&
           fabs(a.blueComponent - b.blueComponent) < 1e-6 && fabs(a.alphaComponent - b.alphaComponent) < 1e-6;
}
static void CheckColors(NSString *name, NSDictionary *theme, BOOL dark, SourceFixture *source, ConsoleFixture *console, PreviewFixture *preview) {
    NSArray *pairs = @[@[@"EditorBackground", source.backgroundColor ?: NSNull.null], @[@"EditorText", source.textColor ?: NSNull.null],
                       @[@"EditorInsertionPoint", source.insertionPointColor ?: NSNull.null],
                       @[@"ConsoleBackground", console.outputText.backgroundColor ?: NSNull.null],
                       @[@"ConsoleText", console.outputText.textColor ?: NSNull.null],
                       @[@"PreviewBackground", preview.themePaperColor ?: NSNull.null]];
    for (NSArray *pair in pairs) {
        NSString *key = pair[0]; NSColor *shown = pair[1] == NSNull.null ? nil : pair[1];
        NSColor *expected = DocumentColor(theme, key, dark);
        if (!expected) continue;
        Check(Same(shown, expected) && fabs([shown colorUsingColorSpace:NSColorSpace.sRGBColorSpace].alphaComponent - 1) < 1e-6,
              [NSString stringWithFormat:@"%@ %@ %@ is the document's opaque color", name, dark ? @"dark" : @"light", key]);
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    SourceFixture *source = [[SourceFixture alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    source.string = @"\\section{x}";
    NSWindow *sourceWindow = Window(source);
    ConsoleFixture *console = [ConsoleFixture new];
    console.outputText = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    console.window = Window(console.outputText);
    PreviewFixture *preview = [[PreviewFixture alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    preview.experimentViewReady = YES;
    NSWindow *previewWindow = Window(preview);
    int themes = 0;
    // Every bundled theme, and each one again with every color stored at opacity 0.3,
    // as a theme edited in Settings can store it.
    NSMutableArray *all = [NSMutableArray array], *names = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:@(argv[i])];
        NSString *name = @(argv[i]).lastPathComponent.stringByDeletingPathExtension;
        [all addObject:theme]; [names addObject:name];
        NSMutableDictionary *faded = [theme mutableCopy];
        for (NSString *key in theme) {
            NSArray *value = theme[key];
            if ([value isKindOfClass:NSArray.class] && value.count == 4 && ![key hasSuffix:@"Alpha"])
                faded[key] = @[value[0], value[1], value[2], @0.3];
        }
        [all addObject:faded]; [names addObject:[name stringByAppendingString:@" (faded)"]];
    }
    for (NSUInteger i = 0; i < all.count; i++) {
        NSDictionary *theme = all[i];
        NSString *name = names[i];
        themes++;
        for (int mode = 0; mode < 2; mode++) {
            BOOL dark = mode == 1;
            NSApp.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            // Opening: the theme of the current appearance.
            liteColors = dark ? nil : theme; darkColors = dark ? theme : nil;
            [source updateExperimentColors:nil]; [console updateConsoleColors:nil]; [preview updateExperimentColors:nil];
            CheckColors(name, theme, dark, source, console, preview);
            // A live theme edit in Settings sends the theme being edited.
            liteColors = darkColors = @{};
            NSNotification *edit = [NSNotification notificationWithName:@"SourceColorChanged" object:nil userInfo:theme];
            [source updateExperimentColors:edit]; [console updateConsoleColors:edit]; [preview updateExperimentColors:edit];
            CheckColors([name stringByAppendingString:@" (edited)"], theme, dark, source, console, preview);
        }
    }
    // The case that was reported: SolarizedDark's editor background has opacity 0.
    NSDictionary *solarized = @{@"EditorBackground": @[@0.0, @0.169, @0.212, @0.0], @"ConsoleBackground": @[@0.0, @0.169, @0.212, @0.0]};
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    darkColors = solarized;
    [source updateExperimentColors:nil]; [console updateConsoleColors:nil];
    NSColor *background = [source.backgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    Check(background.alphaComponent == 1 && fabs(background.blueComponent - 0.212) < 1e-6, @"a background stored with opacity 0 is drawn opaque");
    Check([console.outputText.backgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace].alphaComponent == 1,
          @"a console background stored with opacity 0 is drawn opaque");
    // A theme without the keys gets the built-in colors, as before.
    darkColors = @{};
    [source updateExperimentColors:nil];
    Check(Same(source.insertionPointColor, [[TSColorSupport sharedInstance] darkColorWithKey:@"EditorInsertionPoint"]),
          @"a theme without the key gets the built-in color");
    Check(!sourceWindow.isVisible && !console.window.isVisible && !previewWindow.isVisible, @"no window is shown");
    if (failures) return 1;
    printf("PASS: the Experiment source, console and preview draw the document's opaque theme colors, %d themes (bundled and faded), %d checks\n", themes, checks);
} return 0; }
'''
for name, value in {'SUPPORT': support, 'SOURCE': source, 'CONSOLE': console, 'PREVIEW': preview}.items():
    program = program.replace(f'@@{name}@@', value)
themes = sorted((root / 'Resources/TeXShop/Themes').glob('*.plist')) + sorted((root / 'Resources/Themes').glob('*.plist'))
assert len(themes) >= 11 and any('SolarizedDark' in t.name for t in themes)
with tempfile.TemporaryDirectory(prefix='texshop-experiment-theme-opacity-') as tmp:
    tmp = Path(tmp)
    (tmp / 'test.m').write_text(program, encoding='latin-1')
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                    str(tmp / 'test.m'), '-o', str(tmp / 'test')], check=True)
    (tmp / 'home/Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(tmp / 'test'), *map(str, themes)], capture_output=True, text=True, timeout=120,
                            env=dict(os.environ, HOME=str(tmp / 'home'), CFFIXED_USER_HOME=str(tmp / 'home')))
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
