// The macro editor's contents use the source font, or the console font when
// Settings asks for it, and the text, background and insertion point colors of
// the light or dark theme that matches the window. No window is shown and the
// defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSMacroEditor.h"
#import "TSColorSupport.h"
#import "TSSyntaxHighlighter.h"
#import "TSSyntaxMacroContentScanner.h"
#import "TSSyntaxTeXScanner.h"
#import "TSAdvancedFindTextView.h"
// Only the classes the editor's methods name.
@interface TSTextView : NSTextView
@end
@implementation TSTextView
@end
@implementation TSAdvancedFindController
@end
#import "globals.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
@implementation TSMacroEditor
#include "MacroContentAppearance.inc"
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
@end
static BOOL Same(NSColor *a, NSColor *b) {
    NSColor *x=[a colorUsingColorSpace:NSColorSpace.genericRGBColorSpace], *y=[b colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    return x && y && fabs(x.redComponent-y.redComponent)<.002 && fabs(x.greenComponent-y.greenComponent)<.002 && fabs(x.blueComponent-y.blueComponent)<.002 && fabs(x.alphaComponent-y.alphaComponent)<.002;
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    liteColors = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])];
    darkColors = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])];
    REQUIRE(liteColors && darkColors);
    TSMacroEditor *editor = [TSMacroEditor new];
    NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,300,200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    NSTextView *contents = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,300,200)];
    host.contentView = contents;
    [editor setValue:host forKey:@"window"]; [editor setValue:contents forKey:@"contentTextView"];
    // Fonts.
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSFont *source = [NSFont fontWithName:@"Menlo-Regular" size:15];
    [defaults setObject:[NSArchiver archivedDataWithRootObject:source] forKey:DocumentFontKey];
    [defaults setBool:NO forKey:SameFontForMacroKey];
    REQUIRE([[editor contentFont] isEqual:source]);
    [defaults setBool:YES forKey:SameFontForMacroKey];
    [defaults setObject:@"Courier" forKey:ConsoleFontNameKey]; [defaults setFloat:11 forKey:ConsoleFontSizeKey];
    REQUIRE([[[editor contentFont] familyName] isEqual:@"Courier"] && [editor contentFont].pointSize == 11);
    [defaults setBool:NO forKey:SameFontForMacroKey]; [defaults removeObjectForKey:DocumentFontKey];
    REQUIRE([[editor contentFont] isEqual:[NSFont userFontOfSize:12]]);
    // Colors follow the window's appearance and are the opaque colors the
    // document's source uses (colorFromDictionary:andKey:), whatever alpha the
    // theme stores: the bundled Solarized Light has a transparent background.
    TSColorSupport *colors = [TSColorSupport sharedInstance];
    NSArray *lightBackground = liteColors[@"EditorBackground"];
    REQUIRE(lightBackground.count == 4 && [lightBackground[3] doubleValue] < 0.01);
    NSMutableDictionary *translucent = [darkColors mutableCopy];
    NSMutableArray *faint = [darkColors[@"EditorBackground"] mutableCopy]; faint[3] = @0.3; translucent[@"EditorBackground"] = faint;
    for (NSDictionary *dark in @[darkColors, translucent]) {
        darkColors = dark;
        for (NSAppearanceName mode in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            BOOL isDark = [mode isEqual:NSAppearanceNameDarkAqua];
            NSDictionary *theme = isDark ? darkColors : liteColors;
            host.appearance = [NSAppearance appearanceNamed:mode];
            [editor applyContentAppearance:nil];
            REQUIRE(contents.drawsBackground);
            for (NSArray *pair in @[@[@"EditorBackground", contents.backgroundColor], @[@"EditorText", contents.textColor], @[@"EditorInsertionPoint", contents.insertionPointColor]]) {
                NSColor *document = [colors colorFromDictionary:theme andKey:pair[0]];
                REQUIRE(document != nil && Same(pair[1], document) && [pair[1] alphaComponent] > 0.999);
            }
            REQUIRE(Same(contents.typingAttributes[NSForegroundColorAttributeName], contents.textColor));
            contents.string = @"\\begin{#SEL#}#INS#";
            REQUIRE(Same([contents.textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] ?: contents.textColor, contents.textColor));
        }
    }
    // A theme without the key uses the built-in color, made opaque.
    NSMutableDictionary *partial = [liteColors mutableCopy]; [partial removeObjectForKey:@"EditorInsertionPoint"]; liteColors = partial;
    host.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; [editor applyContentAppearance:nil];
    REQUIRE(Same(contents.insertionPointColor, [[colors colorForKey:@"EditorInsertionPoint" fromDictionary:partial isWindowDark:NO] colorWithAlphaComponent:1]));
    REQUIRE(!Same([colors colorFromDictionary:liteColors andKey:@"EditorText"], [colors colorFromDictionary:darkColors andKey:@"EditorText"]));
    puts("PASS: macro contents use the source or console font and the light or dark theme colors");
} return 0; }
