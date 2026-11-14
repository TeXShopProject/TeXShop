// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxColorScheme.h"
#import "TSColorSupport.h"

// Where a role finds its color when the theme does not define its key.
typedef NS_ENUM(NSInteger, TSSyntaxThemeFallback) {
    TSSyntaxThemeFallbackNone,           // shown as plain text
    TSSyntaxThemeFallbackBuiltIn,        // the built-in color of a light or a dark window
    TSSyntaxThemeFallbackYellow,         // yellow in either window
    TSSyntaxThemeFallbackCommand,        // the color of commands, if the theme has one
};

typedef struct {
    TSSyntaxRole role;
    __unsafe_unretained NSString *key;
    TSSyntaxThemeFallback fallback;
    BOOL underlined;
} TSSyntaxRoleThemeKey;

// The one table of roles and theme keys. A role that is not here is shown as plain text.
static const TSSyntaxRoleThemeKey TSSyntaxRoleThemeKeys[] = {
    {TSSyntaxRoleCommand, @"SyntaxCommand", TSSyntaxThemeFallbackNone, NO},
    {TSSyntaxRoleComment, @"SyntaxComment", TSSyntaxThemeFallbackNone, NO},
    {TSSyntaxRoleMarker, @"SyntaxMarker", TSSyntaxThemeFallbackNone, NO},
    // Without its own key, a bracket takes the marker color (TSColorSupport), then the built-in color.
    {TSSyntaxRoleBracketParen, @"SyntaxMarkerParen", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleBracketCurly, @"SyntaxMarkerCurly", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleBracketSquare, @"SyntaxMarkerSquare", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleIndex, @"SyntaxIndex", TSSyntaxThemeFallbackYellow, NO},
    {TSSyntaxRoleFootnote, @"FootnoteColor", TSSyntaxThemeFallbackCommand, NO},
    {TSSyntaxRoleExplVariable, @"explVariable", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleExplFunction, @"explFunction", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleExplIntenseVariable, @"explIntenseVariable", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleExplIntenseFunction, @"explIntenseFunction", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleExplMessage, @"explmsg", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleExplKey, @"explmykey", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleExplKeyArgument, @"explmykeyArgument", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleXMLComment, @"XMLComment", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleXMLTag, @"XMLTag", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleXMLSpecial, @"XMLSpecial", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleXMLParameter, @"XMLParameter", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleXMLValue, @"XMLValue", TSSyntaxThemeFallbackBuiltIn, NO},
    // AppleScript in the macro editor uses the colors that the source already has.
    {TSSyntaxRoleString, @"XMLValue", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleKeyword, @"SyntaxCommand", TSSyntaxThemeFallbackNone, NO},
    {TSSyntaxRoleNumber, @"XMLSpecial", TSSyntaxThemeFallbackBuiltIn, NO},
    {TSSyntaxRoleRawEvent, @"XMLSpecial", TSSyntaxThemeFallbackBuiltIn, NO},
    // A placeholder is underlined, to tell it from $ and & in the same color.
    {TSSyntaxRolePlaceholder, @"SyntaxMarker", TSSyntaxThemeFallbackNone, YES},
    {TSSyntaxRoleMark, @"SyntaxMarker", TSSyntaxThemeFallbackNone, NO},
};

static NSDictionary<NSAttributedStringKey, id> *TSSyntaxAttributes(NSAttributedStringKey key, NSColor *_Nullable color)
{
    if (color == nil)
        return @{};
    return @{key: (NSColor *_Nonnull)color};
}

static NSColor *_Nullable TSSyntaxThemeColor(NSDictionary *theme, const TSSyntaxRoleThemeKey *entry, BOOL dark)
{
    TSColorSupport *support = [TSColorSupport sharedInstance];
    NSColor *color = [support colorFromDictionary:theme andKey:entry->key];
    if (color)
        return color;
    switch (entry->fallback) {
        case TSSyntaxThemeFallbackNone:
            return nil;
        case TSSyntaxThemeFallbackBuiltIn:
            return dark ? [support darkColorAndAlphaWithKey:entry->key] : [support liteColorAndAlphaWithKey:entry->key];
        case TSSyntaxThemeFallbackYellow:
            return [NSColor colorWithRed:1.0 green:1.0 blue:0.0 alpha:1.0];
        case TSSyntaxThemeFallbackCommand:
            return [support colorFromDictionary:theme andKey:@"SyntaxCommand"];
    }
    return nil;
}

// Fullwidth characters show the foreground and the background that the theme gives them, if any. A theme made
// before these keys existed shows them like other text, and a transparent background adds none.
static NSDictionary<NSAttributedStringKey, id> *TSSyntaxFullwidthAttributes(NSDictionary *theme)
{
    TSColorSupport *support = [TSColorSupport sharedInstance];
    NSMutableDictionary<NSAttributedStringKey, id> *attributes = [NSMutableDictionary dictionary];
    NSColor *color = [support colorFromDictionary:theme andKey:@"EditorHighlightZenkakuSymbol"];
    if (color)
        attributes[NSForegroundColorAttributeName] = color;
    NSArray *background = theme[@"EditorHighlightZenkakuSymbolBackground"];
    if (background.count >= 4)
        color = [support colorAndAlphaFromDictionary:theme andKey:@"EditorHighlightZenkakuSymbolBackground"];
    else
        color = [support colorFromDictionary:theme andKey:@"EditorHighlightZenkakuSymbolBackground"];
    if (color && color.alphaComponent > 0)
        attributes[NSBackgroundColorAttributeName] = color;
    return [attributes copy];
}

@interface TSSyntaxColorScheme ()
@property (nonatomic, readonly, copy) NSDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *attributes;
@end

@implementation TSSyntaxColorScheme

- (instancetype)initWithTheme:(NSDictionary<NSString *, id> *)theme dark:(BOOL)dark
{
    NSMutableDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *attributes = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < sizeof(TSSyntaxRoleThemeKeys) / sizeof(TSSyntaxRoleThemeKeys[0]); i++) {
        const TSSyntaxRoleThemeKey *entry = &TSSyntaxRoleThemeKeys[i];
        NSDictionary<NSAttributedStringKey, id> *role = TSSyntaxAttributes(NSForegroundColorAttributeName, TSSyntaxThemeColor(theme, entry, dark));
        if (entry->underlined) {
            // The underline has the color of the text, given as a color of its own so that whoever removes its own
            // attributes can tell this underline by it.
            NSMutableDictionary<NSAttributedStringKey, id> *underlined = [role mutableCopy];
            underlined[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
            if (role[NSForegroundColorAttributeName])
                underlined[NSUnderlineColorAttributeName] = role[NSForegroundColorAttributeName];
            role = [underlined copy];
        }
        attributes[@(entry->role)] = role;
    }
    attributes[@(TSSyntaxRoleFullwidthSymbol)] = TSSyntaxFullwidthAttributes(theme);

    TSColorSupport *support = [TSColorSupport sharedInstance];
    // The active line falls back to the built-in color of a light window, in a dark one too.
    NSColor *activeLine = [support colorFromDictionary:theme andKey:@"EntryColor"] ?: [support liteColorAndAlphaWithKey:@"EntryColor"];
    return [self initWithAttributes:attributes
               activeLineAttributes:TSSyntaxAttributes(NSBackgroundColorAttributeName, activeLine)
          braceHighlightAttributes:TSSyntaxAttributes(NSForegroundColorAttributeName, [support colorFromDictionary:theme andKey:@"EditorHighlightBraces"])
        contentHighlightAttributes:TSSyntaxAttributes(NSBackgroundColorAttributeName, [support colorFromDictionary:theme andKey:@"EditorHighlightContent"])];
}

- (instancetype)initWithAttributes:(NSDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *)attributes
                activeLineAttributes:(NSDictionary<NSAttributedStringKey, id> *)activeLineAttributes
           braceHighlightAttributes:(NSDictionary<NSAttributedStringKey, id> *)braceHighlightAttributes
         contentHighlightAttributes:(NSDictionary<NSAttributedStringKey, id> *)contentHighlightAttributes
{
    if ((self = [super init])) {
        // Immutable all the way down: what the caller passes in may change later.
        NSMutableDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *copied = [NSMutableDictionary dictionary];
        [attributes enumerateKeysAndObjectsUsingBlock:^(NSNumber *role, NSDictionary<NSAttributedStringKey, id> *roleAttributes, BOOL *stop) {
            copied[role] = [roleAttributes copy];
        }];
        _attributes = [copied copy];
        _activeLineAttributes = [activeLineAttributes copy];
        _braceHighlightAttributes = [braceHighlightAttributes copy];
        _contentHighlightAttributes = [contentHighlightAttributes copy];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesForRole:(TSSyntaxRole)role
{
    return self.attributes[@(role)] ?: @{};
}

@end
