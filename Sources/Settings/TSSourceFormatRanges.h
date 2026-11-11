// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import <math.h>

// Ranges of the whole-number settings in Settings > Editor > Format. The
// settings fields and the source windows use the same ranges, so a stored
// value outside them (from an older version or from the defaults command)
// is shown and applied as the nearest whole number inside the range.
typedef struct {
    NSInteger minimum;
    NSInteger maximum;
} TSIntegerRange;

static const TSIntegerRange TSTabWidthRange = {2, 50};
static const TSIntegerRange TSParagraphIndentRange = {0, 100};
static const TSIntegerRange TSInterlineSpaceRange = {1, 20};

static inline NSInteger TSIntegerInRange(double value, TSIntegerRange range)
{
    if (isnan(value)) return range.minimum;
    value = MIN((double)range.maximum, MAX((double)range.minimum, value));
    return (NSInteger)trunc(value);
}

static inline NSInteger TSStoredIntegerInRange(NSUserDefaults *defaults, NSString *key, TSIntegerRange range)
{
    return TSIntegerInRange([defaults doubleForKey:key], range);
}
