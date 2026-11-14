// SPDX-License-Identifier: GPL-2.0-or-later
// What the application gives the Advanced Find panel's fields and the rules of Multiple Replace
// (TSAppDelegate.m, "Advanced Find field style"): the opaque text, background and insertion point colors of the
// light or dark theme, the source font, the TeX settings of syntax coloring, the theme's colors only with syntax
// coloring on, and a new style whenever the themes, the syntax settings or the source font change. Built by
// Tests/run-advanced-find-field-style.py; no window is shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSColorSupport.h"
#import "TSSyntaxColorScheme.h"
#import "TSSyntaxTeXOptions.h"
#import "TSAdvancedFindFieldStyle.h"
#import "TSPreferenceEffects.h"
#import "globals.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)

#include "AdvancedFindFieldStyle.inc"

static BOOL Same(NSColor *a, NSColor *b)
{
    NSColor *x = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *y = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return x && y && fabs(x.redComponent - y.redComponent) < .002 && fabs(x.greenComponent - y.greenComponent) < .002
        && fabs(x.blueComponent - y.blueComponent) < .002 && fabs(x.alphaComponent - y.alphaComponent) < .002;
}

static NSColor *Opaque(NSDictionary *theme, NSString *key)
{
    NSArray<NSNumber *> *rgb = theme[key];
    return [NSColor colorWithRed:rgb[0].doubleValue green:rgb[1].doubleValue blue:rgb[2].doubleValue alpha:1];
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    liteColors = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])];
    darkColors = [NSDictionary dictionaryWithContentsOfFile:@(argv[2])];
    REQUIRE(liteColors && darkColors);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:SyntaxColoringEnabledKey];
    TSInstallAdvancedFindFieldStyle();
    REQUIRE(TSAdvancedFindFieldStyle.provider != nil);

    // The colors of the theme of a light or a dark window, opaque as the source shows them: the bundled Solarized
    // Light stores a transparent background.
    REQUIRE([liteColors[@"EditorBackground"][3] doubleValue] < 0.01);
    for (NSNumber *dark in @[@NO, @YES]) {
        NSDictionary *theme = dark.boolValue ? darkColors : liteColors;
        TSAdvancedFindFieldStyle *style = TSAdvancedFindFieldStyle.provider(dark.boolValue);
        REQUIRE(Same(style.textColor, Opaque(theme, @"EditorText")) && Same(style.backgroundColor, Opaque(theme, @"EditorBackground"))
                && Same(style.insertionPointColor, Opaque(theme, @"EditorInsertionPoint")) && style.backgroundColor.alphaComponent > 0.999);
        // The theme's colors of the syntax roles, the regular expression roles from the keys of the source.
        REQUIRE(style.scheme && Same([style.scheme attributesForRole:TSSyntaxRoleCommand][NSForegroundColorAttributeName], Opaque(theme, @"SyntaxCommand")));
        REQUIRE(Same([style.scheme attributesForRole:TSSyntaxRoleRegexEscape][NSForegroundColorAttributeName], Opaque(theme, @"explIntenseFunction")));
        REQUIRE(Same([style.scheme attributesForRole:TSSyntaxRoleRegexSymbol][NSForegroundColorAttributeName], Opaque(theme, @"SyntaxMarkerParen")));
        REQUIRE(style.texOptions.marksFullwidthSymbols == ([style.scheme attributesForRole:TSSyntaxRoleFullwidthSymbol].count > 0));
    }
    REQUIRE(!Same(TSAdvancedFindFieldStyle.provider(NO).textColor, TSAdvancedFindFieldStyle.provider(YES).textColor));
    // A theme without the key: the built-in color, opaque.
    NSDictionary *saved = liteColors;
    NSMutableDictionary *partial = [liteColors mutableCopy];
    [partial removeObjectForKey:@"EditorInsertionPoint"];
    liteColors = partial;
    REQUIRE(Same(TSAdvancedFindFieldStyle.provider(NO).insertionPointColor,
                 [[[TSColorSupport sharedInstance] colorForKey:@"EditorInsertionPoint" fromDictionary:partial isWindowDark:NO] colorWithAlphaComponent:1]));
    liteColors = saved;

    // Syntax coloring off: no scheme, the theme's text and background still.
    [defaults setBool:NO forKey:SyntaxColoringEnabledKey];
    TSAdvancedFindFieldStyle *off = TSAdvancedFindFieldStyle.provider(NO);
    REQUIRE(off.scheme == nil && Same(off.textColor, Opaque(liteColors, @"EditorText")) && Same(off.backgroundColor, Opaque(liteColors, @"EditorBackground")));
    [defaults setBool:YES forKey:SyntaxColoringEnabledKey];

    // The TeX settings of the source.
    for (NSNumber *on in @[@YES, @NO]) {
        BOOL b = on.boolValue;
        g_texChar = b ? 0x00A5 : '\\';
        [defaults setBool:b forKey:expl3SyntaxColoringKey];
        [defaults setBool:!b forKey:MakeatletterEnabledKey];
        [defaults setBool:b forKey:IndexColorStartKey];
        [defaults setBool:!b forKey:SyntaxColorFootnoteKey];
        TSSyntaxTeXOptions *tex = TSAdvancedFindFieldStyle.provider(NO).texOptions;
        REQUIRE(tex.texCharacter == (b ? 0x00A5 : '\\') && tex.colorsExpl3 == b && tex.makesAtLetter == !b && tex.colorsIndex == b && tex.colorsFootnote == !b);
    }

    // The source font, or the user font of 12 points.
    NSFont *source = [NSFont fontWithName:@"Menlo-Regular" size:15];
    [defaults setObject:[NSArchiver archivedDataWithRootObject:source] forKey:DocumentFontKey];
    REQUIRE([TSAdvancedFindFieldStyle.provider(NO).font isEqual:source]);
    [defaults removeObjectForKey:DocumentFontKey];
    REQUIRE([TSAdvancedFindFieldStyle.provider(NO).font isEqual:[NSFont userFontOfSize:12]]);

    // The fields follow the themes, syntax coloring, expl3 and \makeatletter, and the source font.
    __block NSUInteger changes = 0;
    [NSNotificationCenter.defaultCenter addObserverForName:TSAdvancedFindFieldStyleDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *notification) { changes++; }];
    NSArray<NSNotificationName> *names = @[SourceColorChangedNotification, DocumentSyntaxColorNotification, TSPreferenceNeedsRecolorNotification,
                                           DocumentFontChangedNotification];
    for (NSNotificationName name in names) {
        NSUInteger before = changes;
        [NSNotificationCenter.defaultCenter postNotificationName:name object:nil];
        REQUIRE(changes == before + 1);
    }
    // The settings that post them.
    REQUIRE([TSPreferenceNotificationsForKeys([NSSet setWithObject:DocumentFontKey]) containsObject:DocumentFontChangedNotification]);
    REQUIRE([TSPreferenceNotificationsForKeys([NSSet setWithObject:SyntaxColoringEnabledKey]) containsObject:DocumentSyntaxColorNotification]);
    REQUIRE([TSPreferenceNotificationsForKeys([NSSet setWithObject:expl3SyntaxColoringKey]) containsObject:TSPreferenceNeedsRecolorNotification]);
    REQUIRE([TSPreferenceNotificationsForKeys([NSSet setWithObject:DefaultLiteThemeKey]) containsObject:SourceColorChangedNotification]);
    puts("PASS: the Advanced Find fields get the theme of the window, the source font and the TeX settings, and follow their changes");
} return 0; }
