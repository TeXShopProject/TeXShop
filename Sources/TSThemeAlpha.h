// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#import <Cocoa/Cocoa.h>
typedef NSString *TSThemeAlphaKey NS_TYPED_EXTENSIBLE_ENUM;
static TSThemeAlphaKey const TSThemeSourceAlphaKey = @"SourceAlpha";
static TSThemeAlphaKey const TSThemePreviewAlphaKey = @"PreviewAlpha";
static TSThemeAlphaKey const TSThemeConsoleAlphaKey = @"ConsoleAlpha";
static inline CGFloat TSThemeWindowAlpha(NSDictionary *theme, TSThemeAlphaKey key) {
    id value = theme[key];
    if (![value isKindOfClass:NSArray.class] || [value count] < 4) return 1;
    id alpha = value[3];
    if (![alpha isKindOfClass:NSNumber.class]) return 1;
    double result = [alpha doubleValue];
    return isfinite(result) && result >= 0 && result <= 1 ? result : 1;
}

static inline NSColor *TSThemeWindowAlphaColor(NSDictionary *theme, TSThemeAlphaKey key) {
    id value = theme[key];
    CGFloat rgb[3] = {0, 0, 0};
    if ([value isKindOfClass:NSArray.class] && [value count] >= 3) {
        for (NSUInteger i = 0; i < 3; i++) {
            id component = value[i];
            if ([component isKindOfClass:NSNumber.class] && isfinite([component doubleValue]))
                rgb[i] = MIN(1, MAX(0, [component doubleValue]));
        }
    }
    return [NSColor colorWithSRGBRed:rgb[0] green:rgb[1] blue:rgb[2] alpha:TSThemeWindowAlpha(theme, key)];
}
