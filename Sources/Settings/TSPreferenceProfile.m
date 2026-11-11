// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceProfile.h"
#import "globals.h"
#import "TSDockIcon.h"
static TSPreferenceKey const TSProfileKeyDarkModeInvertPreview = @"DarkModeInvertPreview";

static TSPreferenceKey const TSProfileKeyAppleLanguages = @"AppleLanguages";
static TSPreferenceKey const TSProfileKeyApplePersistence = @"ApplePersistence";
static TSPreferenceKey const TSProfileKeyAutoReloadExternalPDF = @"AutoReloadExternalPDF";
static TSPreferenceKey const TSProfileKeyContiguousTextLayout = @"ContiguousTextLayout";
static TSPreferenceKey const TSProfileKeyConvertToBackslash = @"ConvertToBackslash";
static TSPreferenceKey const TSProfileKeyConvertToYen = @"ConvertToYen";
static TSPreferenceKey const TSProfileKeyFullwidthSpaceCharacterKindExtended = @"FullwidthSpaceCharacterKindExtended";
static TSPreferenceKey const TSProfileKeyNSUserKeyEquivalents = @"NSUserKeyEquivalents";
static TSPreferenceKey const TSProfileKeyNewLineCharacterKindExtended = @"NewLineCharacterKindExtended";
static TSPreferenceKey const TSProfileKeySpaceCharacterKindExtended = @"SpaceCharacterKindExtended";
static TSPreferenceKey const TSProfileKeyTSMenuShortcutOverrides = @"TSMenuShortcutOverrides";
TSPreferenceKey const TSSettingsSelectedCategoryKey = @"TSSettingsSelectedCategory";
static TSPreferenceKey const TSProfileKeyTSPreviewAppearanceMode = @"TSPreviewAppearanceMode";
static TSPreferenceKey const TSProfileKeyTabCharacterKindExtended = @"TabCharacterKindExtended";

static NSUInteger profileApplicationDepth;
BOOL TSPreferenceProfileIsApplying(void) { return profileApplicationDepth != 0; }
NSSet<TSPreferenceKey> *TSKnownPreferenceKeys(void)
{
    static NSSet<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[
            AcceptFirstMouseKey,
            AggressiveTrashAUXKey,
            AltPathKey,
            AlternateEngineKey,
            AlwaysHighlightEnabledKey,
            AntiAliasKey,
            TSProfileKeyAppleLanguages,
            TSProfileKeyApplePersistence,
            AutoCompleteEnabledKey,
            AutoOpenRootFileKey,
            TSProfileKeyAutoReloadExternalPDF,
            AutoSaveEnabledKey,
            AutomaticDashSubstitutionKey,
            AutomaticDataDetectionKey,
            AutomaticLinkDetectionKey,
            AutomaticQuoteSubstitutionKey,
            AutomaticSpellingCorrectionEnabledKey,
            AutomaticTextReplacementKey,
            AutomaticUTF8MACtoUTF8ConversionKey,
            BeepEnabledKey,
            BibDeskCompletionKey,
            BibTeXengineKey,
            BlockCursorKey,
            BlockCursorBKey,
            BlockCursorGKey,
            BlockCursorRKey,
            BlockSideKey,
            BlockWidthKey,
            BringFrontOnTypesetKey,
            BringPdfFrontOnAutomaticUpdateKey,
            BringPdfFrontOnTypesetKey,
            CheckBraceEnabledKey,
            CheckBracketEnabledKey,
            CheckParenEnabledKey,
            CheckSquareBracketEnabledKey,
            ColorImmediatelyKey,
            CommandCompletionAlternateMarkShortcutKey,
            CommandCompletionCharKey,
            ConTeXtTagsKey,
            ConsoleBackgroundAlphaKey,
            ConsoleBackgroundColor_BKey,
            ConsoleBackgroundColor_GKey,
            ConsoleBackgroundColor_RKey,
            ConsoleBehaviorKey,
            ConsoleFontNameKey,
            ConsoleFontSizeKey,
            ConsoleForegroundColor_BKey,
            ConsoleForegroundColor_GKey,
            ConsoleForegroundColor_RKey,
            ConsoleWidthResizeKey,
            ConsoleWindowNameKey,
            ConsoleWindowAlphaKey,
            ConsoleWindowFixedPosKey,
            ConsoleWindowPosModeKey,
            TSProfileKeyContiguousTextLayout,
            ConvertLFKey,
            TSProfileKeyConvertToBackslash,
            TSProfileKeyConvertToYen,
            CreateLabelListKey,
            CreateTagListKey,
            TSProfileKeyDarkModeInvertPreview,
            DefaultCommandKey,
            DefaultDarkThemeKey,
            DefaultEngineKey,
            DefaultLiteThemeKey,
            DefaultScriptKey,
            DisplayAsBookKey,
            DistillerCommandKey,
            TSDockIconKey,
            DocumentFontKey,
            DocumentFontAttributesKey,
            DocumentSplitWindowPositionKey,
            DocumentWindowNameKey,
            DocumentWindowFixedPosKey,
            DocumentWindowPosModeKey,
            EditorCanAddBracketsKey,
            EncodingKey,
            EncodingAutoDetectionKey,
            EncodingMenuInSaveDialogKey,
            ExceptionListExcludesParametersKey,
            ExperimentMouseModeKey,
            ExternalEditorTypesetAtStartKey,
            ExtraCommandsNotToCheckParametersKey,
            ExtraCommandsToCheckParametersKey,
            FindMethodKey,
            FlashBackgroundEnabledKey,
            FlashDelayKey,
            FlashFixKey,
            FullwidthSpaceCharacterKindKey,
            TSProfileKeyFullwidthSpaceCharacterKindExtended,
            GSBinPath,
            HighlightContentEnabledKey,
            HtmlHomeKey,
            HtmlWindowFixedPosKey,
            HtmlWindowNameKey,
            HtmlWindowPosModeKey,
            IgnoreStartOnRebootKey,
            IncrementalSearchKey,
            IndexColorStartKey,
            InterpolationValueKey,
            KeepBackupKey,
            KpsetoolKey,
            LPanelOutlinesKey,
            LastStyNameKey,
            LatexCommandKey,
            LatexGSCommandKey,
            LatexPanelNameKey,
            LatexScriptCommandKey,
            LeftRightArrowsAlwaysPageKey,
            LineBreakModeKey,
            LineNumberEnabledKey,
            LineNumberSizeKey,
            LinkPopupsKey,
            MPanelOriginXKey,
            MPanelOriginYKey,
            MakeEmptyDocumentKey,
            MakeatletterEnabledKey,
            MathExpressionCompletionKey,
            MiniaturizeRootFileKey,
            TSProfileKeyNSUserKeyEquivalents,
            NewLineCharacterKindKey,
            TSProfileKeyNewLineCharacterKindExtended,
            NoScrollPageTurnKey,
            OpenAsTabsKey,
            OpenWithSourceInFrontKey,
            originalSpellingKey,
            OtherEditorSyncKey,
            OtherTeXExtensionsKey,
            OtherTrashExtensionsKey,
            PanelOriginXKey,
            PanelOriginYKey,
            ParensMatchingEnabledKey,
            PdfBack_AKey,
            PdfBack_BKey,
            PdfBack_GKey,
            PdfBack_RKey,
            PdfColorMapKey,
            PdfColorParam1Key,
            PdfColorParam2Key,
            PdfCopyTypeKey,
            PdfExportTypeKey,
            PdfFileRefreshKey,
            PdfFirstPageStyleKey,
            PdfFitSizeKey,
            PdfFore_AKey,
            PdfFore_BKey,
            PdfFore_GKey,
            PdfFore_RKey,
            PdfKitFitSizeKey,
            PdfKitMouseModeKey,
            PdfKitWindowNameKey,
            PdfMagnificationKey,
            PdfMouseModeKey,
            PdfPageStyleKey,
            PdfQuickDragKey,
            PdfRefreshKey,
            PdfWindowNameKey,
            PdfWindowFixedPosKey,
            PdfWindowPosModeKey,
            PdfPageBack_BKey,
            PdfPageBack_GKey,
            PdfPageBack_RKey,
            PortableDocumentWindowFixedPosKey,
            PortablePdfWindowFixedPosKey,
            PreviewDrawerOpenKey,
            PreviewWindowAlphaKey,
            RedConsoleAfterErrorKey,
            RefreshTimeKey,
            ResetSourceTextColorEachTimeKey,
            reverseSyncBlueKey,
            reverseSyncGreenKey,
            reverseSyncRedKey,
            RightJustifyKey,
            RightJustifyIfAnyKey,
            SameFontForMacroKey,
            SaveDocumentFontKey,
            SavePSEnabledKey,
            SaveRelatedKey,
            ShowFullPathEnabledKey,
            showFullwidthSpaceCharacterKey,
            ShowIndicatorForMoveEnabledKey,
            ShowInvisibleCharactersEnabledKey,
            showNewLineCharacterKey,
            showSpaceCharacterKey,
            ShowSyncMarksKey,
            showTabCharacterKey,
            SmartInsertDeleteKey,
            SourceAndPreviewInSameWindowKey,
            SourceFirstLineHeadIndentKey,
            SourceHeadIndentKey,
            SourceInterlineSpaceKey,
            SourceWindowAlphaKey,
            SpaceCharacterKindKey,
            TSProfileKeySpaceCharacterKindExtended,
            SparkleAutomaticUpdateKey,
            SparkleIntervalKey,
            SpellCheckEnabledKey,
            spellingAutomaticDefaultKey,
            spellingLanguageDefaultKey,
            SwitchSidesKey,
            SyncMethodKey,
            SyncUseTabsKey,
            SyntaxColorEntryLineKey,
            SyntaxColorFootnoteKey,
            SyntaxColoringEnabledKey,
            TSHasBeenUsedKey,
            TSProfileKeyTSMenuShortcutOverrides,
            TSSettingsSelectedCategoryKey,
            TSProfileKeyTSPreviewAppearanceMode,
            TabCharacterKindKey,
            TSProfileKeyTabCharacterKindExtended,
            TabIndentKey,
            tabsAlsoForInputFilesKey,
            TagMenuInMenuBarKey,
            TagSectionsKey,
            TSTeXAwareSpellCheckingKey,
            TetexBinPath,
            TexCommandKey,
            TexGSCommandKey,
            TexScriptCommandKey,
            TextMateSyncKey,
            TurnOffCommandSpellCheckKey,
            TurnOffCommentSpellCheckKey,
            TurnOffParameterSpellCheckKey,
            UseExternalEditorKey,
            UseNewTagsAndLabelsKey,
            UseOldHeadingCommandsKey,
            UseOutlineKey,
            UseTransparencyKey,
            UserInfoPath,
            WarnForShellEscapeKey,
            WatchServerKey,
            XMLChapterTagKey,
            XMLConclusionTagKey,
            XMLExercisesTagKey,
            XMLFigureTagKey,
            XMLIntroductionTagKey,
            XMLMarkTagKey,
            XMLProjectTagKey,
            XMLSectionTagKey,
            XMLSubsectionTagKey,
            XMLSubsubsectionTagKey,
            XMLTableTagKey,
            backgroundAlphaKey,
            background_BKey,
            background_GKey,
            background_RKey,
            brieflyFlashYellowForMatchKey,
            commandblueKey,
            commandgreenKey,
            commandredKey,
            commentblueKey,
            commentgreenKey,
            commentredKey,
            expl3SyntaxColoringKey,
            foreground_BKey,
            foreground_GKey,
            foreground_RKey,
            fullscreenPageStyleKey,
            fullscreenResizeOptionKey,
            highlightBracesBlueKey,
            highlightBracesGreenKey,
            highlightBracesRedKey,
            highlightContentBlueKey,
            highlightContentGreenKey,
            highlightContentRedKey,
            indexblueKey,
            indexgreenKey,
            indexredKey,
            insertionpoint_BKey,
            insertionpoint_GKey,
            insertionpoint_RKey,
            invisibleCharBlueKey,
            invisibleCharGreenKey,
            invisibleCharRedKey,
            markerblueKey,
            markergreenKey,
            markerredKey,
            MatrixSizeKey,
            ptexUtfOutputEnabledKey,
            syncWithRedOvalsKey,
            tabsKey
        ]];
    });
    return keys;
}

BOOL TSPreferenceProfilePreservesKey(TSPreferenceKey key)
{
    if ([key hasPrefix:@"SU"] || [key hasPrefix:@"NSWindow Frame "] ||
        [key hasPrefix:@"NSToolbar Configuration "] || [key hasPrefix:@"NSSplitView Subview Frames "] ||
        [key hasPrefix:@"TSSettingsUI"]) return YES;
    return [@[
        TSProfileKeyAppleLanguages,
        ConsoleWindowNameKey,
        DocumentSplitWindowPositionKey,
        DocumentWindowNameKey,
        HtmlWindowNameKey,
        LastStyNameKey,
        LatexPanelNameKey,
        MPanelOriginXKey,
        MPanelOriginYKey,
        TSProfileKeyNSUserKeyEquivalents,
        PanelOriginXKey,
        PanelOriginYKey,
        PdfKitWindowNameKey,
        PdfWindowNameKey,
        SparkleAutomaticUpdateKey,
        SparkleIntervalKey,
        TSProfileKeyTSMenuShortcutOverrides,
        TSSettingsSelectedCategoryKey
    ] containsObject:key];
}

@interface TSPreferenceProfile ()
@property (copy) NSDictionary<NSString *, id> *registeredDefaults;
@end

@implementation TSPreferenceProfile
- (nullable instancetype)initWithProfile:(NSDictionary<NSString *, id> *)profile documentFont:(NSData *)fontData
{
    return [self initWithProfile:profile documentFont:fontData registeredDefaults:@{}];
}
- (nullable instancetype)initWithProfile:(NSDictionary<NSString *, id> *)profile documentFont:(NSData *)fontData registeredDefaults:(NSDictionary<NSString *, id> *)registeredDefaults
{
    if (![profile isKindOfClass:NSDictionary.class] || fontData.length == 0) return nil;
    id path = profile[TetexBinPath];
    if (![path isKindOfClass:NSString.class] ||
        [[path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] == 0) return nil;
    if (![NSPropertyListSerialization propertyList:profile isValidForFormat:NSPropertyListBinaryFormat_v1_0]) return nil;
    self = [super init];
    if (self == nil) return nil;
    NSMutableDictionary<NSString *, id> *updates = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *removals = [NSMutableSet set];
    for (NSString *key in TSKnownPreferenceKeys()) {
        if (TSPreferenceProfilePreservesKey(key)) continue;
        id value = profile[key];
        if (value != nil) updates[key] = value;
        else [removals addObject:key];
    }
    updates[TSProfileKeyConvertToYen] = @YES;
    [removals removeObject:TSProfileKeyConvertToYen];
    _registeredDefaults = [registeredDefaults copy];
    updates[TSHasBeenUsedKey] = @YES;
    updates[DocumentFontKey] = fontData;
    [removals removeObject:TSHasBeenUsedKey];
    [removals removeObject:DocumentFontKey];
    // Reset attributed-font overrides alongside the standard document font.
    [updates removeObjectForKey:DocumentFontAttributesKey];
    [removals addObject:DocumentFontAttributesKey];
    _updates = [updates copy];
    _removals = [removals copy];
    _enginePath = [path copy];
    return self;
}

- (void)applyToDefaults:(NSUserDefaults *)defaults
{
    NSAssert(NSThread.isMainThread, @"Apply a preference profile on the main thread");
    profileApplicationDepth++;
    @try {
        [defaults registerDefaults:self.registeredDefaults];
        for (NSString *key in self.removals) [defaults removeObjectForKey:key];
        [self.updates enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            [defaults setObject:value forKey:key];
        }];
    } @finally {
        profileApplicationDepth--;
    }
    // Observers of individual defaults changes were deferred above.
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
}
@end
