// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
typedef NSString *TSPreferenceKey NS_TYPED_EXTENSIBLE_ENUM;

static TSPreferenceKey const TSTeXAwareSpellCheckingKey = @"TeXAwareSpellChecking";
static TSPreferenceKey const TSCommandCompletionCharacterKey = @"CommandCompletionChar";

// Shared by preference controls and the shortcut provider.
static NSNotificationName const TSCompletionChangedNotification = @"CommandCompletionCharNotification";

static NSNotificationName const TSFindMethodChangedNotification = @"TSFindMethodChangedNotification";

// Open documents that still use the spelling dictionary chosen in Settings follow a new choice.
static NSNotificationName const TSSpellingLanguageChangedNotification = @"TSSpellingLanguageChangedNotification";
