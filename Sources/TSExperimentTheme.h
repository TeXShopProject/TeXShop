#pragma once
#import <Cocoa/Cocoa.h>

static inline CGFloat TSExperimentWindowAlpha(NSDictionary *theme, NSString *key) {
    id value = theme[key];
    if (![value isKindOfClass:NSArray.class] || [value count] < 4) return 1;
    id alpha = value[3];
    if (![alpha isKindOfClass:NSNumber.class]) return 1;
    CGFloat result = [alpha doubleValue];
    return isfinite(result) ? MIN(1, MAX(0, result)) : 1;
}
