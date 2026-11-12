// SPDX-License-Identifier: GPL-2.0-or-later
//
// The spelling dictionary chosen in Settings › Spell Checking. The stored value
// is a spell checker language identifier (for example "en", or "en_GB"); people
// see the language's own name for it, as in the system Spelling panel.
#import <Cocoa/Cocoa.h>
#import "globals.h"

NS_ASSUME_NONNULL_BEGIN

// The identifier with "-" written as "_" and surrounding spaces removed.
static inline NSString *TSSpellingLanguageNormalized(NSString *_Nullable language)
{
    NSString *trimmed = [language ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [trimmed stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
}

// The name shown for a spell checker language: the language's own name, as the
// Spelling panel shows it. The checker's "en" is U.S. English.
static inline NSString *TSSpellingLanguageDisplayName(NSString *language)
{
    NSString *identifier = TSSpellingLanguageNormalized(language);
    if ([identifier isEqualToString:@"en"]) identifier = @"en_US";
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
    NSString *name = [locale displayNameForKey:NSLocaleIdentifier value:identifier];
    if (name.length == 0) return language;
    NSRange first = [name rangeOfComposedCharacterSequenceAtIndex:0];
    return [name stringByReplacingCharactersInRange:first
        withString:[[name substringWithRange:first] uppercaseStringWithLocale:locale]];
}

// The language in `available` that a stored value names, or nil. The checker
// takes "en_US" for "en" and "de_DE" for "de"; earlier versions stored names
// such as "English".
static inline NSString *_Nullable TSSpellingLanguageMatching(NSString *_Nullable stored, NSArray<NSString *> *available)
{
    NSString *wanted = TSSpellingLanguageNormalized(stored);
    if (wanted.length == 0) return nil;
    for (NSString *language in available)
        if ([TSSpellingLanguageNormalized(language) caseInsensitiveCompare:wanted] == NSOrderedSame) return language;
    NSRange underscore = [wanted rangeOfString:@"_"];
    if (underscore.location != NSNotFound) {
        NSString *base = [wanted substringToIndex:underscore.location];
        for (NSString *language in available)
            if ([TSSpellingLanguageNormalized(language) caseInsensitiveCompare:base] == NSOrderedSame) return language;
        return nil;
    }
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en"];
    for (NSString *language in available) {
        NSString *identifier = TSSpellingLanguageNormalized(language);
        if ([identifier rangeOfString:@"_"].location != NSNotFound) continue;
        NSString *name = [english localizedStringForLanguageCode:identifier];
        if (name != nil && [name caseInsensitiveCompare:wanted] == NSOrderedSame) return language;
    }
    return nil;
}

// Titles of the "Automatic Language" choice in every localization. Versions
// 5.60 beta-3 to beta-9 stored the title instead of choosing automatic
// detection when the interface was not in English.
static inline BOOL TSSpellingLanguageIsAutomaticTitle(NSString *_Nullable stored)
{
    static NSSet<NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet<NSString *> *found = [NSMutableSet setWithObject:@"Automatic Language"];
        NSBundle *bundle = NSBundle.mainBundle;
        for (NSString *localization in bundle.localizations) {
            NSString *path = [bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:localization];
            NSString *title = path ? [NSDictionary dictionaryWithContentsOfFile:path][@"Automatic Language"] : nil;
            if ([title isKindOfClass:NSString.class] && title.length > 0) [found addObject:title];
        }
        NSString *current = NSLocalizedString(@"Automatic Language", @"");
        if (current.length > 0) [found addObject:current];
        titles = [[NSSet alloc] initWithSet:found];
    });
    NSString *trimmed = [stored ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [titles containsObject:trimmed];
}

// The Settings choice: YES for automatic language detection. *language is ""
// with automatic detection; otherwise the language in `available` that the
// stored value names, as Settings shows it, or the stored value if none does.
static inline BOOL TSSpellingDefaultIsAutomatic(NSUserDefaults *defaults, NSArray<NSString *> *_Nullable available,
                                                NSString *_Nonnull *_Nullable language)
{
    NSString *stored = [defaults stringForKey:spellingLanguageDefaultKey] ?: @"";
    BOOL automatic = [defaults boolForKey:spellingAutomaticDefaultKey] || TSSpellingLanguageIsAutomaticTitle(stored);
    if (language != NULL)
        *language = automatic ? @"" : (TSSpellingLanguageMatching(stored, available ?: @[]) ?: stored);
    return automatic;
}

NS_ASSUME_NONNULL_END
