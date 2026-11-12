// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSPreferenceKey.h"
#import "globals.h"
#import "TSInvisibleCharacters.h"
#import "TSDockIcon.h"
NS_ASSUME_NONNULL_BEGIN
static NSNotificationName const TSPreferenceEncodingChangedNotification = @"EncodingChangedNotification";
static NSNotificationName const TSPreferenceNeedsRecolorNotification = @"NeedsForRecolorNotification";

typedef NS_OPTIONS(NSUInteger, TSPreferencePreparation) {
    TSPreferencePrepareNone = 0,
    TSPreferencePrepareEncoding = 1 << 0,
    TSPreferencePrepareSpelling = 1 << 1,
    TSPreferencePrepareTheme = 1 << 2,
    TSPreferencePrepareDock = 1 << 3,
    TSPreferencePreparePDFCopy = 1 << 4
};
// Preparation always completes before observers receive a change notification.
static inline TSPreferencePreparation TSPreferencePreparationsForKeys(NSSet<TSPreferenceKey> *changed) {
    NSDictionary<NSNumber *, NSArray<TSPreferenceKey> *> *groups = @{
        @(TSPreferencePrepareEncoding): @[EncodingKey, ptexUtfOutputEnabledKey],
        @(TSPreferencePrepareSpelling): @[TSTeXAwareSpellCheckingKey, TurnOffCommandSpellCheckKey, TurnOffParameterSpellCheckKey, TurnOffCommentSpellCheckKey, ExceptionListExcludesParametersKey, ExtraCommandsNotToCheckParametersKey, ExtraCommandsToCheckParametersKey],
        @(TSPreferencePrepareTheme): @[DefaultLiteThemeKey, DefaultDarkThemeKey],
        @(TSPreferencePrepareDock): @[TSDockIconKey],
        @(TSPreferencePreparePDFCopy): @[PdfCopyTypeKey]
    };
    TSPreferencePreparation result = TSPreferencePrepareNone;
    for (NSNumber *effect in groups) {
        NSArray<TSPreferenceKey> *keys = groups[effect];
        if (keys != nil && [changed intersectsSet:[NSSet setWithArray:keys]]) result |= effect.unsignedIntegerValue;
    }
    return result;
}

// One dependency table for individual actions, validated text and profile updates.
static inline NSArray<NSNotificationName> *TSPreferenceNotificationsForKeys(NSSet<TSPreferenceKey> *changed) {
    NSDictionary<NSNotificationName, NSArray<TSPreferenceKey> *> *groups = @{
        DocumentFontChangedNotification: @[DocumentFontKey, DocumentFontAttributesKey, tabsKey, SourceFirstLineHeadIndentKey, SourceHeadIndentKey, SourceInterlineSpaceKey],
        ConsoleFontChangedNotification: @[ConsoleFontNameKey, ConsoleFontSizeKey],
        DocumentSyntaxColorNotification: @[SyntaxColoringEnabledKey, SyntaxColorEntryLineKey],
        DocumentAutoCompleteNotification: @[AutoCompleteEnabledKey],
        DocumentBibDeskCompleteNotification: @[BibDeskCompletionKey],
        ExternalEditorNotification: @[UseExternalEditorKey],
        SourceColorChangedNotification: @[DefaultLiteThemeKey, DefaultDarkThemeKey],
        TSPreferenceEncodingChangedNotification: @[EncodingKey, ptexUtfOutputEnabledKey],
        TSCompletionChangedNotification: @[CommandCompletionCharKey],
        TSFindMethodChangedNotification: @[FindMethodKey, IncrementalSearchKey],
        TSSpellingLanguageChangedNotification: @[spellingLanguageDefaultKey, spellingAutomaticDefaultKey],
        TSPreferenceNeedsRecolorNotification: @[AlwaysHighlightEnabledKey, ShowIndicatorForMoveEnabledKey, HighlightContentEnabledKey, BeepEnabledKey, FlashBackgroundEnabledKey, CheckBraceEnabledKey, CheckBracketEnabledKey, CheckSquareBracketEnabledKey, CheckParenEnabledKey, MakeatletterEnabledKey, expl3SyntaxColoringKey, ShowInvisibleCharactersEnabledKey, showSpaceCharacterKey, showFullwidthSpaceCharacterKey, showNewLineCharacterKey, showTabCharacterKey, SpaceCharacterKindKey, FullwidthSpaceCharacterKindKey, NewLineCharacterKindKey, TabCharacterKindKey, TSInvisibleExtendedKey(SpaceCharacterKindKey), TSInvisibleExtendedKey(FullwidthSpaceCharacterKindKey), TSInvisibleExtendedKey(NewLineCharacterKindKey), TSInvisibleExtendedKey(TabCharacterKindKey)]
    };
    NSMutableOrderedSet<NSNotificationName> *result = [NSMutableOrderedSet orderedSet];
    for (NSNotificationName name in [[groups allKeys] sortedArrayUsingSelector:@selector(compare:)])
        if ([changed intersectsSet:[NSSet setWithArray:groups[name] ?: @[]]]) [result addObject:name];
    return result.array;
}
static inline void TSPostPreferenceNotifications(NSSet<TSPreferenceKey> *changed, NSObject *sender) {
    for (NSNotificationName name in TSPreferenceNotificationsForKeys(changed))
        [NSNotificationCenter.defaultCenter postNotificationName:name object:sender];
}
static inline NSNotificationName _Nullable TSPreferenceNotificationForKey(TSPreferenceKey key) {
    return TSPreferenceNotificationsForKeys([NSSet setWithObject:key]).firstObject;
}
NS_ASSUME_NONNULL_END
