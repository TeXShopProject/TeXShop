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
