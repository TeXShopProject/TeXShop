#!/usr/bin/env python3
"""A theme that has lost its colors (its file emptied or edited elsewhere) still shows readable text.

The color readers of TSColorSupport are compiled verbatim. For an empty theme, in the light and in the dark mode:
the text and background of the source, the console and the log differ enough to read (contrast 4.5 or more); the
document's source, console and log views get these colors from the production part of
-[TSDocument changeColorsUsingDictionary:] (real NSTextViews), the Experiment console from the production
-[TSExperimentConsoleController updateConsoleColors:], and the Settings wells (-colorForKey:fromDictionary:) show
the same colors. Nothing is written into the theme, and nothing is shown on screen. --mutations removes each part
and the test must then fail.

Also a theme that lacks any set of the colors that go in pairs (one to all eight of EditorText, EditorBackground,
EditorInsertionPoint, EntryColor, ConsoleText, ConsoleBackground, LogText, LogBackground), for every bundled theme, one
of the user's own with white text and LiteTheme without an active line, in both appearances: the missing color is chosen so that the text reads (contrast
4.5 or more) and the other one is kept; checked for the source, console and log of a document, the Experiment console
(-updateConsoleColors:), the Experiment source (-[ScrapTextView updateExperimentColors:]), the cursor and the active
line."""
from pathlib import Path
import subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
support = (root / 'Sources/Editor/TSColorSupport.m').read_text(encoding='utf-8')
signatures = ['- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *) colorAndAlphaFromDictionary:',
              '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:', '- (NSColor *)liteColorAndAlphaWithKey:', '- (NSColor *)darkColorAndAlphaWithKey:',
              '- (NSColor *)colorForKey: (NSString *)theKey fromDictionary:', '- (NSColor *)opaqueColorForKey: (NSString *)theKey fromDictionary:']
readers = [method(support, s) for s in signatures]
document_source = (root / 'Sources/Editor/TSDocument-Color.m').read_text(encoding='utf-8')
start = document_source.index('    myBackgroundColor = [[TSColorSupport sharedInstance] ')
end = document_source.index('    [outputText setBackgroundColor: myBackgroundColor];\n') + len('    [outputText setBackgroundColor: myBackgroundColor];\n')
document = document_source[start:end]
console_source = (root / 'Sources/Typesetting/TSExperimentConsoleController.m').read_text(encoding='utf-8')
console = method(console_source, '- (void)updateConsoleColors:(NSNotification *)notification\n{')
scrap_source = (root / 'Sources/Editor/ScrapTextView.m').read_text(encoding='utf-8')
scrap = method(scrap_source, '- (void)updateExperimentColors:(NSNotification *)notification')
fragments = [('complete method:' + s, support, m) for s, m in zip(signatures, readers)]
fragments.append(('complete method:updateExperimentColors', scrap_source, scrap))
scheme_source = (root / 'Sources/Syntax/TSSyntaxColorScheme.m').read_text(encoding='utf-8')
scheme = scheme_source[scheme_source.index('// Where a role finds its color'):]
fragments.append(('color scheme', scheme_source, scheme))
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
- (NSColor *)liteColorAndAlphaWithKey:(NSString *)theKey;
- (NSColor *)darkColorAndAlphaWithKey:(NSString *)theKey;
- (NSColor *)colorFromDictionary:(NSDictionary *)theDictionary andKey:(NSString *)theKey;
- (NSColor *)colorAndAlphaFromDictionary:(NSDictionary *)theDictionary andKey:(NSString *)theKey;
- (NSArray *)colorArrayFromDictionary:(NSDictionary *)theDictionary andKey:(NSString *)theKey;
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
__READERS__
@end
#import "TSSyntaxColorScheme.h"
__SCHEME__
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

// The Experiment source with its production -updateExperimentColors:.
@interface ScrapText : NSTextView
@end
@implementation ScrapText
__SCRAP__
@end

static double Channel(double c) { return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static double Luminance(NSColor *color)
{
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return 0.2126 * Channel(rgb.redComponent) + 0.7152 * Channel(rgb.greenComponent) + 0.0722 * Channel(rgb.blueComponent);
}
// Whether lightnesses in [0, 1] for the lacking places of a chain (places in order, each pair of neighbours a
// pair that must read, a contrast of at least ratio) can be found: in x = ln(L + 0.05) a pair reads when its x are at
// least ln(ratio) apart. Each place keeps the x it can take given the places before it, as a list of intervals.
static BOOL ChainFeasible(NSUInteger count, const double *fixedLightness, const BOOL *lacking, const double *ratio)
{
    double sets[8][16][2]; NSUInteger sizes[8] = {0};
    for (NSUInteger k = 0; k < count; k++) {
        double a = lacking[k] ? log(0.05) : log(fixedLightness[k] + 0.05), b = lacking[k] ? log(1.05) : a;
        if (k == 0 || (!lacking[k] && !lacking[k - 1]) || ratio[k - 1] <= 1) { sets[k][0][0] = a; sets[k][0][1] = b; sizes[k] = 1; }
        else {
            double d = log(ratio[k - 1]);
            sizes[k] = 0;
            // x such that some x' of the place before is at least d away.
            for (NSUInteger i = 0; i < sizes[k - 1]; i++) {
                double lo = sets[k - 1][i][0], hi = sets[k - 1][i][1];
                double below[2] = {a, fmin(b, hi - d)}, above[2] = {fmax(a, lo + d), b};
                if (below[0] <= below[1] && sizes[k] < 16) { sets[k][sizes[k]][0] = below[0]; sets[k][sizes[k]][1] = below[1]; sizes[k]++; }
                if (above[0] <= above[1] && sizes[k] < 16) { sets[k][sizes[k]][0] = above[0]; sets[k][sizes[k]][1] = above[1]; sizes[k]++; }
            }
        }
        if (sizes[k] == 0) return NO;
    }
    return YES;
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
            // An empty theme looks like the Lite or the Dark theme.
            if (theme.count == 0) {
                NSColor *paper = [[colors opaqueColorForKey:@"ConsoleBackground" fromDictionary:theme isWindowDark:dark] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                REQUIRE(dark ? fabs(paper.redComponent - 0.114) < 0.002 && fabs(paper.blueComponent - 0.179) < 0.002
                             : fabs(paper.redComponent - 0.996) < 0.002 && fabs(paper.blueComponent - 0.918) < 0.002);
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
    // A theme that has lost one color of a pair, in a light and in a dark window (any theme can be used for either):
    // the missing one is chosen so that the text reads, and the color the theme still has is kept.
    NSString *folder = @(argv[1]);
    NSMutableDictionary *named = [NSMutableDictionary dictionary];
    for (NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:NULL])
        if ([file hasSuffix:@".plist"]) named[file.stringByDeletingPathExtension] = [NSDictionary dictionaryWithContentsOfFile:[folder stringByAppendingPathComponent:file]];
    REQUIRE(named.count >= 9 && named[@"Dracula"] && named[@"LiteTheme"]);
    NSMutableDictionary *mine = [named[@"LiteTheme"] mutableCopy];
    for (NSString *key in @[@"EditorText", @"ConsoleText", @"LogText", @"EditorInsertionPoint"]) mine[key] = @[@1, @1, @1, @1];
    for (NSString *key in @[@"EditorBackground", @"ConsoleBackground", @"LogBackground", @"EntryColor"]) mine[key] = @[@0.1, @0.1, @0.1, @1];
    named[@"Mine (white text)"] = mine;
    NSMutableDictionary *noActiveLine = [named[@"LiteTheme"] mutableCopy];
    [noActiveLine removeObjectForKey:@"EntryColor"];
    named[@"LiteTheme without an active line"] = noActiveLine;
    // A theme of the user's own whose pairs read only on a middle gray (6th audit): black text, a white cursor.
    NSMutableDictionary *gray = [named[@"LiteTheme"] mutableCopy];
    gray[@"EditorText"] = @[@0, @0, @0, @1]; gray[@"EditorInsertionPoint"] = @[@1, @1, @1, @1];
    gray[@"EditorBackground"] = gray[@"EntryColor"] = @[@0.459, @0.459, @0.459, @1];
    named[@"Mine (middle gray)"] = gray;
    // The 7th audit: text #040404, cursor white, background and active line #767676; and with text and cursor swapped.
    NSMutableDictionary *boundary = [named[@"LiteTheme"] mutableCopy];
    boundary[@"EditorText"] = @[@(4 / 255.0), @(4 / 255.0), @(4 / 255.0), @1]; boundary[@"EditorInsertionPoint"] = @[@1, @1, @1, @1];
    boundary[@"EditorBackground"] = boundary[@"EntryColor"] = @[@(118 / 255.0), @(118 / 255.0), @(118 / 255.0), @1];
    named[@"Mine (boundary)"] = boundary;
    NSMutableDictionary *swapped = [boundary mutableCopy];
    swapped[@"EditorText"] = boundary[@"EditorInsertionPoint"]; swapped[@"EditorInsertionPoint"] = boundary[@"EditorText"];
    named[@"Mine (boundary, swapped)"] = swapped;
    // The 1st audit of the gray refinement: text #000006, cursor #F0FFF3, background and active line #498146 (both pairs
    // just above 4.5); and swapped.
    NSMutableDictionary *exact = [named[@"LiteTheme"] mutableCopy];
    exact[@"EditorText"] = @[@0, @0, @(6 / 255.0), @1]; exact[@"EditorInsertionPoint"] = @[@(240 / 255.0), @1, @(243 / 255.0), @1];
    exact[@"EditorBackground"] = exact[@"EntryColor"] = @[@(73 / 255.0), @(129 / 255.0), @(70 / 255.0), @1];
    named[@"Mine (exact boundary)"] = exact;
    NSMutableDictionary *exactSwapped = [exact mutableCopy];
    exactSwapped[@"EditorText"] = exact[@"EditorInsertionPoint"]; exactSwapped[@"EditorInsertionPoint"] = exact[@"EditorText"];
    named[@"Mine (exact boundary, swapped)"] = exactSwapped;
    // The 2nd audit of the gray refinement: fractional components, background and active line #767676, text and cursor
    // grays reading exactly 4.5 on it (to 2e-13).
    NSMutableDictionary *fraction = [named[@"LiteTheme"] mutableCopy];
    fraction[@"EditorText"] = @[@0.9956969919249633, @0.9956969919249633, @0.9956969919249633, @1];
    fraction[@"EditorInsertionPoint"] = @[@0.017698230157346905, @0.017698230157346905, @0.017698230157346905, @1];
    fraction[@"EditorBackground"] = fraction[@"EntryColor"] = @[@(118 / 255.0), @(118 / 255.0), @(118 / 255.0), @1];
    named[@"Mine (fractional boundary)"] = fraction;
    // Any of the colors of the pairs lacking, one to all eight (a theme may never have had some, and may lose
    // others); in both appearances.
    NSArray *keys = @[@"EditorText", @"EditorBackground", @"EditorInsertionPoint", @"EntryColor", @"ConsoleText", @"ConsoleBackground", @"LogText", @"LogBackground"];
    NSArray *drawn = @[@[@"EditorText", @"EditorBackground"], @[@"EditorInsertionPoint", @"EditorBackground"], @[@"EditorText", @"EntryColor"],
                       @[@"ConsoleText", @"ConsoleBackground"], @[@"LogText", @"LogBackground"]];
    NSMutableArray *losses = [NSMutableArray array];
    for (NSUInteger bits = 1; bits < (1u << keys.count); bits++) {
        NSMutableArray *lost = [NSMutableArray array];
        for (NSUInteger i = 0; i < keys.count; i++) if (bits & (1u << i)) [lost addObject:keys[i]];
        [losses addObject:lost];
    }
    NSUInteger checked = 0, pairsChecked = 0, drawnChecked = 0;
    for (NSString *name in [named.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        for (int dark = 0; dark <= 1; dark++) {
            mode = dark ? "dark" : "light";
            NSDictionary *whole = named[name];
            for (NSArray *lost in losses) {
                NSMutableDictionary *theme = [whole mutableCopy];
                [theme removeObjectsForKeys:lost];
                NSDictionary *before = [theme copy];
                NSMutableDictionary *color = [NSMutableDictionary dictionary];
                for (NSString *key in keys) color[key] = [colors opaqueColorForKey:key fromDictionary:theme isWindowDark:dark];
                // The colors the theme still has are kept.
                for (NSString *key in keys)
                    if (![lost containsObject:key] && [colors colorFromDictionary:whole andKey:key])
                        REQUIRE(SameRGB(color[key], [colors colorFromDictionary:whole andKey:key]));
                // Each drawn pair with a lost color reads, when the theme's own pair read.
                for (NSArray *pair in drawn) {
                    if (![lost containsObject:pair[0]] && ![lost containsObject:pair[1]]) continue;
                    NSColor *wasText = [colors opaqueColorForKey:pair[0] fromDictionary:whole isWindowDark:dark];
                    NSColor *wasBackground = [colors opaqueColorForKey:pair[1] fromDictionary:whole isWindowDark:dark];
                    if (Contrast(wasText, wasBackground) < 4.5) continue;
                    if (Contrast(color[pair[0]], color[pair[1]]) < 4.5)
                        fprintf(stderr, "%s without %s: %s on %s %.2f\n", name.UTF8String, [lost componentsJoinedByString:@"+"].UTF8String,
                                [pair[0] UTF8String], [pair[1] UTF8String], Contrast(color[pair[0]], color[pair[1]]));
                    REQUIRE(Contrast(color[pair[0]], color[pair[1]]) >= 4.5);
                    pairsChecked++;
                }
                // The wells' look-up gives what is drawn.
                for (NSString *key in lost)
                    REQUIRE(SameRGB([colors colorForKey:key fromDictionary:theme isWindowDark:dark], color[key]));
                checked++;
                // What draws them: the document's views, the active line, the Experiment console and source (for up to
                // three lacking colors; they ask the same method as the checks above).
                if (lost.count > 3) continue;
                drawnChecked++;
                Document *document = [Document new];
                document->textView1 = View(); document->textView2 = View(); document->outputText = View(); document.logTextView = View();
                [document applyDictionary:theme dark:dark];
                REQUIRE(SameRGB(document->textView1.textColor, color[@"EditorText"]) && SameRGB(document->textView1.backgroundColor, color[@"EditorBackground"]));
                REQUIRE(SameRGB(document->outputText.textColor, color[@"ConsoleText"]) && SameRGB(document->outputText.backgroundColor, color[@"ConsoleBackground"]));
                REQUIRE(SameRGB(document.logTextView.textColor, color[@"LogText"]) && SameRGB(document.logTextView.backgroundColor, color[@"LogBackground"]));
                TSSyntaxColorScheme *scheme = [[TSSyntaxColorScheme alloc] initWithTheme:theme dark:dark];
                REQUIRE(SameRGB(scheme.activeLineAttributes[NSBackgroundColorAttributeName], color[@"EntryColor"]));
                NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
                host.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                TSExperimentConsoleController *console = [TSExperimentConsoleController new];
                console.window = host;
                console.outputText = View();
                [console updateConsoleColors:[NSNotification notificationWithName:@"colors" object:nil userInfo:theme]];
                REQUIRE(SameRGB(console.outputText.textColor, color[@"ConsoleText"]) && SameRGB(console.outputText.backgroundColor, color[@"ConsoleBackground"]));
                ScrapText *experiment = [[ScrapText alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
                host.contentView = experiment;
                [experiment updateExperimentColors:[NSNotification notificationWithName:@"colors" object:nil userInfo:theme]];
                REQUIRE(SameRGB(experiment.textColor, color[@"EditorText"]) && SameRGB(experiment.backgroundColor, color[@"EditorBackground"])
                        && SameRGB(experiment.insertionPointColor, color[@"EditorInsertionPoint"]));
                REQUIRE([theme isEqual:before]);
            }
        }
    }
    NSArray *(^components)(NSColor *) = ^NSArray *(NSColor *c) { NSColor *rgb = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; return @[@(rgb.redComponent), @(rgb.greenComponent), @(rgb.blueComponent), @1]; };
    // 8-bit themes on the boundary: for each 8-bit background (the 256 grays, and 2000 random colors of the middle lightness), the 8-bit gray
    // text and cursor nearest a contrast of 4.5 on each side that still reach it (text dark and cursor light, and the
    // other way round). Without the background, and without the background and the active line, in both appearances,
    // the text and the cursor read (the background they had shows that they can).
    {
        srand48(18112026);
        NSMutableArray<NSColor *> *backgrounds = [NSMutableArray array];
        for (int g = 0; g < 256; g++) [backgrounds addObject:[NSColor colorWithRed:g / 255.0 green:g / 255.0 blue:g / 255.0 alpha:1]];
        // Random 8-bit colors of the middle lightness, where both a darker and a lighter gray can read (2000 of them).
        for (int r = 0; r < 2000; ) {
            NSColor *c = [NSColor colorWithRed:(lrand48() % 256) / 255.0 green:(lrand48() % 256) / 255.0 blue:(lrand48() % 256) / 255.0 alpha:1];
            double l = Luminance(c);
            if ((l + 0.05) / 0.05 >= 4.5 && 1.05 / (l + 0.05) >= 4.5) { [backgrounds addObject:c]; r++; }
        }
        NSUInteger boundaryCases = 0;
        for (NSColor *background in backgrounds) {
            // The 8-bit grays just reading on the background, darker and lighter.
            NSColor *darker = nil, *lighter = nil;
            for (int g = 255; g >= 0 && !darker; g--) { NSColor *c = [NSColor colorWithRed:g / 255.0 green:g / 255.0 blue:g / 255.0 alpha:1]; if (Luminance(c) < Luminance(background) && Contrast(c, background) >= 4.5) darker = c; }
            for (int g = 0; g < 256 && !lighter; g++) { NSColor *c = [NSColor colorWithRed:g / 255.0 green:g / 255.0 blue:g / 255.0 alpha:1]; if (Luminance(c) > Luminance(background) && Contrast(c, background) >= 4.5) lighter = c; }
            if (!darker || !lighter) continue;
            for (int way = 0; way < 2; way++) {
                NSMutableDictionary *whole = [named[@"LiteTheme"] mutableCopy];
                whole[@"EditorText"] = components(way ? lighter : darker); whole[@"EditorInsertionPoint"] = components(way ? darker : lighter);
                whole[@"EditorBackground"] = whole[@"EntryColor"] = components(background);
                for (NSArray *lost in @[@[@"EditorBackground"], @[@"EditorBackground", @"EntryColor"]])
                    for (int dark = 0; dark <= 1; dark++) {
                        mode = dark ? "dark (8-bit boundary)" : "light (8-bit boundary)";
                        NSMutableDictionary *theme = [whole mutableCopy];
                        [theme removeObjectsForKeys:lost];
                        NSColor *drawnBackground = [colors opaqueColorForKey:@"EditorBackground" fromDictionary:theme isWindowDark:dark];
                        double text = Contrast([colors opaqueColorForKey:@"EditorText" fromDictionary:theme isWindowDark:dark], drawnBackground);
                        double cursor = Contrast([colors opaqueColorForKey:@"EditorInsertionPoint" fromDictionary:theme isWindowDark:dark], drawnBackground);
                        if (text < 4.5 || cursor < 4.5)
                            fprintf(stderr, "8-bit boundary %s without %s: text %.12f, cursor %.12f\n", [[background description] UTF8String], [lost componentsJoinedByString:@"+"].UTF8String, text, cursor);
                        REQUIRE(text >= 4.5 && cursor >= 4.5);
                        REQUIRE(SameRGB([colors colorForKey:@"EditorBackground" fromDictionary:theme isWindowDark:dark], drawnBackground));
                        boundaryCases++;
                    }
            }
        }
        printf("PASS: %lu cases of 8-bit themes on the boundary (text and cursor just reaching 4.5 on the background): without the background, both read at least 4.5\n", (unsigned long)boundaryCases);
    }
    NSColor *(^random)(void) = ^NSColor *(void) { return [NSColor colorWithRed:drand48() green:drand48() blue:drand48() alpha:1]; };
    // Fractional themes on the boundary: a random background of the middle lightness (2000, seeded), and gray text
    // and cursor whose contrast with it is 4.5 plus a window of 1e-12, 1e-11, 1e-9, 1e-6 or 1e-3 (text darker or lighter);
    // the themes whose pairs read (as computed) are taken. Without the background, and without the background and the
    // active line, in both appearances, the text and the cursor read at least 4.5.
    {
        srand48(2611182);
        // The gray of lightness l (sRGB).
        NSColor *(^grayOfLightness)(double) = ^NSColor *(double l) {
            double v = l <= 0.03928 / 12.92 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055;
            return [NSColor colorWithRed:v green:v blue:v alpha:1];
        };
        double windows[5] = {1e-12, 1e-11, 1e-9, 1e-6, 1e-3};
        NSUInteger fractionCases = 0, taken = 0;
        for (int number = 0; number < 2000; number++) {
            NSColor *background;
            double l;
            do { background = random(); l = Luminance(background); } while (!((l + 0.05) * 4.5 - 0.05 <= 1 && (l + 0.05) / 4.5 - 0.05 >= 0));
            double window = windows[number % 5];
            NSColor *darker = grayOfLightness((l + 0.05) / (4.5 + window) - 0.05), *lighter = grayOfLightness((l + 0.05) * (4.5 + window) - 0.05);
            if (Contrast(darker, background) < 4.5 || Contrast(lighter, background) < 4.5) continue;
            taken++;
            for (int way = 0; way < 2; way++) {
                NSMutableDictionary *whole = [named[@"LiteTheme"] mutableCopy];
                whole[@"EditorText"] = components(way ? lighter : darker); whole[@"EditorInsertionPoint"] = components(way ? darker : lighter);
                whole[@"EditorBackground"] = whole[@"EntryColor"] = components(background);
                for (NSArray *lost in @[@[@"EditorBackground"], @[@"EditorBackground", @"EntryColor"]])
                    for (int dark = 0; dark <= 1; dark++) {
                        mode = dark ? "dark (fractional boundary)" : "light (fractional boundary)";
                        NSMutableDictionary *theme = [whole mutableCopy];
                        [theme removeObjectsForKeys:lost];
                        NSColor *drawnBackground = [colors opaqueColorForKey:@"EditorBackground" fromDictionary:theme isWindowDark:dark];
                        double text = Contrast([colors opaqueColorForKey:@"EditorText" fromDictionary:theme isWindowDark:dark], drawnBackground);
                        double cursor = Contrast([colors opaqueColorForKey:@"EditorInsertionPoint" fromDictionary:theme isWindowDark:dark], drawnBackground);
                        if (text < 4.5 || cursor < 4.5)
                            fprintf(stderr, "fractional boundary %d (window %g) without %s: text %.17g, cursor %.17g\n", number, window, [lost componentsJoinedByString:@"+"].UTF8String, text, cursor);
                        REQUIRE(text >= 4.5 && cursor >= 4.5);
                        REQUIRE(SameRGB([colors colorForKey:@"EditorBackground" fromDictionary:theme isWindowDark:dark], drawnBackground));
                        fractionCases++;
                    }
            }
        }
        printf("PASS: %lu cases of %lu fractional themes on the boundary (windows down to 1e-12): without the background, text and cursor read at least 4.5\n", (unsigned long)fractionCases, (unsigned long)taken);
    }
    // Random themes of the user's own (seeded), all of whose pairs read, without each one of the colors that go in
    // pairs and without two random sets of them: the pairs with a lacking color read whenever colors of any lightness
    // would make them read (checked analytically), and the wells' look-up gives the colors drawn.
    srand48(20261118);
    NSColor *(^reading)(NSColor *) = ^NSColor *(NSColor *other) { NSColor *c; do c = random(); while (Contrast(c, other) < 4.5); return c; };
    NSUInteger randomCases = 0, randomPairs = 0, noGrayReads = 0;
    for (int number = 0; number < 2000; number++) {
        NSColor *background = random(), *text = reading(background);
        NSColor *cursor = reading(background), *line = reading(text);
        NSColor *consoleBackground = random(), *consoleText = reading(consoleBackground);
        NSColor *logBackground = random(), *logText = reading(logBackground);
        NSDictionary *whole = @{@"EditorText": components(text), @"EditorBackground": components(background), @"EditorInsertionPoint": components(cursor),
                                @"EntryColor": components(line), @"ConsoleText": components(consoleText), @"ConsoleBackground": components(consoleBackground),
                                @"LogText": components(logText), @"LogBackground": components(logBackground)};
        NSMutableArray *sets = [NSMutableArray array];
        for (NSString *key in keys) [sets addObject:@[key]];
        for (int r = 0; r < 2; r++) {
            NSMutableArray *lost = [NSMutableArray array];
            long bits = 1 + (lrand48() % 255);
            for (NSUInteger i = 0; i < keys.count; i++) if (bits & (1L << i)) [lost addObject:keys[i]];
            [sets addObject:lost];
        }
        int dark = number % 2;
        mode = dark ? "dark (random)" : "light (random)";
        for (NSArray *lost in sets) {
            NSMutableDictionary *theme = [whole mutableCopy];
            [theme removeObjectsForKeys:lost];
            NSMutableDictionary *color = [NSMutableDictionary dictionary];
            for (NSString *key in keys) color[key] = [colors opaqueColorForKey:key fromDictionary:theme isWindowDark:dark];
            for (NSString *key in lost)
                REQUIRE(SameRGB([colors colorForKey:key fromDictionary:theme isWindowDark:dark], color[key]));
            for (NSString *key in keys)
                if (![lost containsObject:key]) REQUIRE(SameRGB(color[key], [colors colorFromDictionary:whole andKey:key]));
            // The pairs with a lacking color, as indexes into keys.
            NSMutableArray *involved = [NSMutableArray array];
            BOOL allRead = YES;
            for (NSArray *pair in drawn) {
                if (![lost containsObject:pair[0]] && ![lost containsObject:pair[1]]) continue;
                [involved addObject:@[@([keys indexOfObject:pair[0]]), @([keys indexOfObject:pair[1]])]];
                allRead = allRead && Contrast(color[pair[0]], color[pair[1]]) >= 4.5;
                randomPairs++;
            }
            if (!allRead) {
                // Could colors of any lightness make them read (the text pairs and the cursor pair), or the text pairs
                // alone? The source is the chain active line - text - background - cursor; the console and the log.
                double light[8]; BOOL lack[8];
                for (NSUInteger i = 0; i < keys.count; i++) { lack[i] = [lost containsObject:keys[i]]; light[i] = lack[i] ? 0 : Luminance(color[keys[i]]); }
                NSUInteger order[4] = {3, 0, 1, 2};
                double sourceLight[4]; BOOL sourceLack[4];
                for (NSUInteger i = 0; i < 4; i++) { sourceLight[i] = light[order[i]]; sourceLack[i] = lack[order[i]]; }
                double all[3] = {4.5, 4.5, 4.5}, textOnly[3] = {4.5, 4.5, 1}, one[1] = {4.5};
                BOOL consoleFeasible = ChainFeasible(2, light + 4, lack + 4, one), logFeasible = ChainFeasible(2, light + 6, lack + 6, one);
                BOOL allFeasible = ChainFeasible(4, sourceLight, sourceLack, all) && consoleFeasible && logFeasible;
                BOOL textFeasible = ChainFeasible(4, sourceLight, sourceLack, textOnly) && consoleFeasible && logFeasible;
                if (allFeasible) fprintf(stderr, "random theme %d without %s: colors of some lightness would read\n", number, [lost componentsJoinedByString:@"+"].UTF8String);
                REQUIRE(!allFeasible);
                // Then the text reads, when it can.
                for (NSArray *pair in drawn) {
                    if ([pair[0] isEqual:@"EditorInsertionPoint"] || (![lost containsObject:pair[0]] && ![lost containsObject:pair[1]])) continue;
                    if (textFeasible) REQUIRE(Contrast(color[pair[0]], color[pair[1]]) >= 4.5);
                }
                noGrayReads++;
            }
            randomCases++;
        }
    }
    printf("PASS: %lu cases of 2000 random themes of the user's own, %lu pairs with a lacking color: they read whenever colors of any lightness could make them read, the text first (in %lu cases nothing could make all of them read), and the wells' look-up gives the colors drawn\n",
           (unsigned long)randomCases, (unsigned long)randomPairs, (unsigned long)noGrayReads);
    printf("PASS: %lu cases (%lu themes x 2 appearances x %lu sets of lacking colors), %lu drawn pairs with a lacking color: they read, the theme's colors are kept, the wells' look-up gives the colors drawn; in %lu cases (up to three lacking) the documents, the active line and the Experiment draw them\n",
           (unsigned long)checked, (unsigned long)named.count, (unsigned long)losses.count, (unsigned long)pairsChecked, (unsigned long)drawnChecked);
} return 0; }
'''


def run(parts, label):
    program = PROGRAM.replace('__READERS__', '\n'.join(parts['readers'])).replace('__DOCUMENT__', parts['document']).replace('__CONSOLE__', parts['console']).replace('__SCRAP__', parts['scrap']).replace('__SCHEME__', parts['scheme'])
    with tempfile.TemporaryDirectory(prefix='texshop-theme-missing-colors-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(root / 'Tests'), *include_args(root),
                        str(folder / 'test.m'), '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        return subprocess.run([str(folder / 'test'), str(root / 'Resources/TeXShop/Themes')], capture_output=True, text=True, timeout=600)


parts = {'readers': readers, 'document': document, 'console': console, 'scrap': scrap, 'scheme': scheme}
result = run(parts, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: a theme without its colors shows text that cannot be read')
if '--mutations' in sys.argv:
    mutations = {
        'no built-in light colors': ('readers', '    if (builtIn != nil)\n        return', '    if (NO)\n        return', 0),
        'no built-in dark colors': ('readers', '    if (builtIn != nil)\n        return', '    if (NO)\n        return', 1),
        'no pairs': ('readers', '    if (chain == nil)\n        return builtIn;', '    return builtIn;', 0),
        'no grays of any lightness': ('readers', '    if (best < 4.5 - 1e-9) {', '    if (NO) {', 0),
        'not the text first': ('readers', 'CGFloat cursor = greatest(^BOOL(CGFloat d) { return solve(text, d, NULL); });',
                               'text = greatest(^BOOL(CGFloat d) { return solve(d, d, NULL); });\n            CGFloat cursor = text;', 0),
        'at the edge of the range': ('readers', 'CGFloat inside = MIN(1e-3, (ranges[j][1] - ranges[j][0]) / 2);', 'CGFloat inside = 0;', 0),
        'below 4.5': ('readers', 'CGFloat enough = log(4.5);', 'CGFloat enough = log(4.5) - 1e-3;', 0),
        'no cursor pair': ('readers', 'bestCursor[bg] = MAX(bestCursor[bg], score(2, bg, 3, c));', 'bestCursor[bg] = 4.5;', 0),
        'no active-line pair': ('readers', 'bestLine[t] = MAX(bestLine[t], score(0, e, 1, t));', 'bestLine[t] = 4.5;', 0),
        'the first pair only': ('readers', 'best = MAX(best, MIN(MIN(score(1, t, 2, bg), bestLine[t]), bestCursor[bg]));', 'best = MAX(best, score(1, t, 2, bg));', 0),
        'the built-in colors not first': ('readers', '@0, @10, @20, @20, nil];', '@50, @50, @50, @50, nil];', 0),
        'the document takes no color': ('document', '[[TSColorSupport sharedInstance] opaqueColorForKey: @"ConsoleText" fromDictionary: colorDictionary isWindowDark: withDarkColors]',
                                        '[[TSColorSupport sharedInstance] colorFromDictionary:colorDictionary andKey: @"ConsoleText"]', None),
    }
    for name, (where, before, after, which) in mutations.items():
        # --mutation=NAME runs that one only (so that the mutations can be run side by side).
        only = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--mutation=')), None)
        if only and name != only:
            continue
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
