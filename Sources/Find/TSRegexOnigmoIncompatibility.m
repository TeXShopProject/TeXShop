// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexOnigmoIncompatibility.h"

@implementation TSRegexOnigmoIncompatibility

- (instancetype)initWithKind:(TSRegexOnigmoIncompatibilityKind)kind term:(NSString *)term marked:(BOOL)marked message:(NSString *)message
{
    if ((self = [super init])) {
        _kind = kind;
        _term = [term copy];
        _marked = marked;
        _message = [message copy];
    }
    return self;
}

@end

@implementation TSRegexFindPattern (OnigmoIncompatibilities)

+ (NSArray<TSRegexOnigmoIncompatibility *> *)onigmoIncompatibilities
{
    static NSArray<TSRegexOnigmoIncompatibility *> *entries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#define TSEntry(k, t, m, text) [[TSRegexOnigmoIncompatibility alloc] initWithKind:TSRegexOnigmoIncompatibility##k term:t marked:m message:text]
        entries = @[
            TSEntry(UnicodeClasses, @"\\d \\w \\s \\b", NO,
                    NSLocalizedStringFromTable(@"Unicode: also full-width digits, kanji, kana and the full-width space.", @"AdvancedFindEngine",
                                               @"Cheat sheet, differences from OgreKit: \\d, \\w, \\s and \\b have their Unicode meaning in ICU.")),
            TSEntry(NamedNumbers, @"(?<name>…)", NO,
                    NSLocalizedStringFromTable(@"Named groups are numbered too, as with OgreKit's “Always capture” on.", @"AdvancedFindEngine",
                                               @"Cheat sheet, differences from OgreKit. “Always capture” is an option of the OgreKit find panel.")),
            TSEntry(LiteralBrace, @"\\{ \\}", YES,
                    NSLocalizedStringFromTable(@"ICU needs \\{ and \\} for literal braces (OgreKit did not).", @"AdvancedFindEngine",
                                               @"Cheat sheet and find field, differences from OgreKit: a brace by itself is an error in ICU.")),
            TSEntry(HexDigit, @"\\h", YES,
                    NSLocalizedStringFromTable(@"In ICU \\h is a horizontal space; in OgreKit it was a hexadecimal digit. For a digit, write [0-9a-fA-F].", @"AdvancedFindEngine",
                                               @"Cheat sheet and find field, differences from OgreKit.")),
            TSEntry(Multiline, @"(?m)", YES,
                    NSLocalizedStringFromTable(@"In ICU (?m) makes ^ and $ match at each line; in OgreKit it made . match line breaks, which is (?s) in ICU.", @"AdvancedFindEngine",
                                               @"Cheat sheet and find field, differences from OgreKit.")),
            TSEntry(Possessive, @"{n}+", YES,
                    NSLocalizedStringFromTable(@"In ICU {n}+ is possessive; in OgreKit it repeated the repetition.", @"AdvancedFindEngine",
                                               @"Cheat sheet and find field, differences from OgreKit.")),
            TSEntry(Keep, @"\\K", YES,
                    NSLocalizedStringFromTable(@"ICU has no \\K. Write the part before it as a look-behind (?<=…).", @"AdvancedFindEngine",
                                               @"Cheat sheet and find field, differences from OgreKit.")),
            TSEntry(Call, @"\\g<name>", YES,
                    NSLocalizedStringFromTable(@"ICU cannot call a group with \\g<name>. Repeat the group's pattern instead.", @"AdvancedFindEngine",
                                               @"Cheat sheet and find field, differences from OgreKit.")),
            TSEntry(Absent, @"(?~…)", YES,
                    NSLocalizedStringFromTable(@"ICU has no absent operator (?~…).", @"AdvancedFindEngine",
                                               @"Cheat sheet and find field, differences from OgreKit.")),
            TSEntry(NegatedProperty, @"\\p{^…}", NO,
                    NSLocalizedStringFromTable(@"Write \\P{…} in ICU.", @"AdvancedFindEngine",
                                               @"Cheat sheet, differences from OgreKit: OgreKit's \\p{^…} is an error in ICU.")),
        ];
#undef TSEntry
    });
    return entries;
}

+ (TSRegexOnigmoIncompatibility *)onigmoIncompatibilityOfKind:(TSRegexOnigmoIncompatibilityKind)kind
{
    for (TSRegexOnigmoIncompatibility *entry in self.onigmoIncompatibilities)
        if (entry.kind == kind)
            return entry;
    NSAssert(NO, @"no OgreKit difference of kind %ld", (long)kind);
    return self.onigmoIncompatibilities[0];
}

@end
