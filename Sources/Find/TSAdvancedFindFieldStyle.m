// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindFieldStyle.h"

NSNotificationName const TSAdvancedFindFieldStyleDidChangeNotification = @"TSAdvancedFindFieldStyleDidChangeNotification";

BOOL TSAdvancedFindAppearanceIsDark(NSAppearance *appearance)
{
    return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
}

static NSColor *TSDynamicColor(NSString *name, unsigned light, unsigned dark)
{
    NSColor *(^rgb)(unsigned) = ^NSColor *(unsigned value) {
        return [NSColor colorWithSRGBRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1];
    };
    NSColor *lightColor = rgb(light), *darkColor = rgb(dark);
    return [NSColor colorWithName:name dynamicProvider:^NSColor *(NSAppearance *appearance) {
        return TSAdvancedFindAppearanceIsDark(appearance) ? darkColor : lightColor;
    }];
}

/// The marks, the same in every theme: made once, so that they are the same objects in every scheme.
static NSDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *TSMarkAttributes(void)
{
    static NSDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *marks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSColor *red = TSDynamicColor(@"AdvancedFindInvalid", 0xD12F1B, 0xFF6B5A);
        NSColor *orange = TSDynamicColor(@"AdvancedFindIncompatible", 0xC86400, 0xFFA14A);
        marks = @{
            @(TSSyntaxRoleRegexIncompatible): @{
                NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick | NSUnderlinePatternDot),
                NSUnderlineColorAttributeName: orange,
                NSForegroundColorAttributeName: orange,
            },
            @(TSSyntaxRoleInvalid): @{
                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                NSUnderlineColorAttributeName: red,
                NSForegroundColorAttributeName: red,
            },
        };
    });
    return marks;
}

static TSAdvancedFindFieldStyle *_Nullable (^TSProvider)(BOOL dark);

@implementation TSAdvancedFindFieldStyle
@synthesize fieldScheme = _fieldScheme;

- (instancetype)initWithScheme:(nullable TSSyntaxColorScheme *)scheme texOptions:(TSSyntaxTeXOptions *)texOptions font:(nullable NSFont *)font
                     textColor:(nullable NSColor *)textColor backgroundColor:(nullable NSColor *)backgroundColor
           insertionPointColor:(nullable NSColor *)insertionPointColor
{
    if ((self = [super init])) {
        _scheme = scheme;
        _texOptions = [texOptions copy];
        _font = font;
        _textColor = textColor;
        _backgroundColor = backgroundColor;
        _insertionPointColor = insertionPointColor;
    }
    return self;
}

- (TSSyntaxColorScheme *)fieldScheme
{
    if (!_fieldScheme) {
        NSMutableDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *roles = [NSMutableDictionary dictionary];
        TSSyntaxColorScheme *scheme = self.scheme;
        for (TSSyntaxRole role = TSSyntaxRoleCommand; scheme && role <= TSSyntaxRoleInvalid; role++) {
            NSDictionary<NSAttributedStringKey, id> *attributes = [scheme attributesForRole:role];
            if (attributes.count > 0)
                roles[@(role)] = attributes;
        }
        [roles addEntriesFromDictionary:TSMarkAttributes()];
        _fieldScheme = [[TSSyntaxColorScheme alloc] initWithAttributes:roles activeLineAttributes:@{}
                                              braceHighlightAttributes:scheme.braceHighlightAttributes ?: @{}
                                            contentHighlightAttributes:scheme.contentHighlightAttributes ?: @{}];
    }
    return _fieldScheme;
}

- (NSFont *)fieldFont
{
    NSFont *font = self.font;
    if (!font)
        return [NSFont monospacedSystemFontOfSize:NSFont.systemFontSize + 1 weight:NSFontWeightRegular];
    CGFloat size = MIN(MAX(font.pointSize, 11), 16);
    return size == font.pointSize ? font : ([NSFont fontWithDescriptor:font.fontDescriptor size:size] ?: font);
}

- (nullable NSAppearance *)fieldAppearance
{
    NSColor *background = [self.backgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!background)
        return nil;
    // Relative luminance, as WCAG defines it: light when black text on it has more contrast than white text.
    CGFloat (^linear)(CGFloat) = ^CGFloat(CGFloat c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); };
    CGFloat luminance = 0.2126 * linear(background.redComponent) + 0.7152 * linear(background.greenComponent) + 0.0722 * linear(background.blueComponent);
    return [NSAppearance appearanceNamed:luminance < 0.18 ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
}

+ (nullable TSAdvancedFindFieldStyle *_Nullable (^)(BOOL))provider
{
    return TSProvider;
}

+ (void)setProvider:(nullable TSAdvancedFindFieldStyle *_Nullable (^)(BOOL))provider
{
    TSProvider = [provider copy];
}

+ (TSAdvancedFindFieldStyle *)styleForAppearance:(NSAppearance *)appearance
{
    TSAdvancedFindFieldStyle *style = TSProvider ? TSProvider(TSAdvancedFindAppearanceIsDark(appearance)) : nil;
    return style ?: [[TSAdvancedFindFieldStyle alloc] initWithScheme:nil texOptions:[TSSyntaxTeXOptions new] font:nil textColor:nil
                                                     backgroundColor:nil insertionPointColor:nil];
}

+ (TSAdvancedFindFieldStyle *)styleForWindow:(nullable NSWindow *)window
{
    NSAppearance *appearance = window.appearance ?: NSApp.effectiveAppearance ?: window.effectiveAppearance ?: NSAppearance.currentDrawingAppearance;
    return [self styleForAppearance:appearance];
}

+ (void)styleDidChange
{
    [NSNotificationCenter.defaultCenter postNotificationName:TSAdvancedFindFieldStyleDidChangeNotification object:nil];
}

@end
