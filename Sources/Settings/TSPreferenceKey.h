// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
typedef NSString *TSPreferenceKey NS_TYPED_EXTENSIBLE_ENUM;

static TSPreferenceKey const TSTeXAwareSpellCheckingKey = @"TeXAwareSpellChecking";
static TSPreferenceKey const TSCommandCompletionCharacterKey = @"CommandCompletionChar";

// The key that triggers command completion: Escape, Tab, or none (command completion
// and its mark moves are off). The saved value is ESCAPE, TAB or NONE; any other value,
// or none at all, means Tab, as in earlier versions.
typedef NS_ENUM(NSInteger, TSCommandCompletionTrigger) {
    TSCommandCompletionTriggerEscape = 0,
    TSCommandCompletionTriggerTab = 1,
    TSCommandCompletionTriggerNone = 2,
};
static NSString * const TSCommandCompletionEscapeValue = @"ESCAPE";
static NSString * const TSCommandCompletionTabValue = @"TAB";
static NSString * const TSCommandCompletionNoneValue = @"NONE";

static inline TSCommandCompletionTrigger TSCommandCompletionTriggerFromDefaults(NSUserDefaults *defaults)
{
    NSString *value = [defaults stringForKey:TSCommandCompletionCharacterKey];
    if ([value isEqualToString:TSCommandCompletionEscapeValue]) return TSCommandCompletionTriggerEscape;
    if ([value isEqualToString:TSCommandCompletionNoneValue]) return TSCommandCompletionTriggerNone;
    return TSCommandCompletionTriggerTab;
}

static inline NSString *TSCommandCompletionValueForTrigger(TSCommandCompletionTrigger trigger)
{
    switch (trigger) {
        case TSCommandCompletionTriggerEscape: return TSCommandCompletionEscapeValue;
        case TSCommandCompletionTriggerNone: return TSCommandCompletionNoneValue;
        default: return TSCommandCompletionTabValue;
    }
}

// The character the source window and the Experiment compare typed keys with, or nil
// when command completion is off.
static inline NSString *TSCommandCompletionCharacterForTrigger(TSCommandCompletionTrigger trigger)
{
    switch (trigger) {
        case TSCommandCompletionTriggerEscape: return @"\033";
        case TSCommandCompletionTriggerNone: return nil;
        default: return @"\t";
    }
}

// Shared by preference controls and the shortcut provider.
static NSNotificationName const TSCompletionChangedNotification = @"CommandCompletionCharNotification";

static NSNotificationName const TSFindMethodChangedNotification = @"TSFindMethodChangedNotification";

// Open documents that still use the spelling dictionary chosen in Settings follow a new choice.
static NSNotificationName const TSSpellingLanguageChangedNotification = @"TSSpellingLanguageChangedNotification";
