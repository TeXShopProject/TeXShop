// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceProfile.h"

static NSUInteger profileApplicationDepth;
BOOL TSPreferenceProfileIsApplying(void) { return profileApplicationDepth != 0; }
NSSet<NSString *> *TSKnownPreferenceKeys(void)
{
    static NSSet<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[
            @"AcceptFirstMouse",
            @"AggressiveTrashAUX",
            @"AltPath",
            @"AlternateEngine",
            @"AlwaysHighlightEnabled",
            @"AntiAlias",
            @"AppleLanguages",
            @"ApplePersistence",
            @"AutoCompleteEnabled",
            @"AutoOpenRootFile",
            @"AutoReloadExternalPDF",
            @"AutoSaveEnabled",
            @"AutomaticDashSubstitution",
            @"AutomaticDataDetection",
            @"AutomaticLinkDetection",
            @"AutomaticQuoteSubstitution",
            @"AutomaticSpellingCorrectionEnabled",
            @"AutomaticTextReplacement",
            @"AutomaticUTF8MACtoUTF8Conversion",
            @"BeepEnabled",
            @"BibDeskCompletion",
            @"BibTeXengine",
            @"BlockCursor",
            @"BlockCursorB",
            @"BlockCursorG",
            @"BlockCursorR",
            @"BlockSide",
            @"BlockWidth",
            @"BringFrontOnTypeset",
            @"BringPdfFrontOnAutomaticUpdate",
            @"BringPdfFrontOnTypeset",
            @"CheckBraceEnabled",
            @"CheckBracketEnabled",
            @"CheckParenEnabled",
            @"CheckSquareBracketEnabled",
            @"ColorImmediately",
            @"CommandCompletionAlternateMarkShortcut",
            @"CommandCompletionChar",
            @"ConTeXtTags",
            @"ConsoleBackgroundAlpha",
            @"ConsoleBackgroundColor_B",
            @"ConsoleBackgroundColor_G",
            @"ConsoleBackgroundColor_R",
            @"ConsoleBehavior",
            @"ConsoleFontName",
            @"ConsoleFontSize",
            @"ConsoleForegroundColor_B",
            @"ConsoleForegroundColor_G",
            @"ConsoleForegroundColor_R",
            @"ConsoleWidthResize",
            @"ConsoleWindow",
            @"ConsoleWindowAlpha",
            @"ConsoleWindowFixedPos",
            @"ConsoleWindowPosMode",
            @"ContiguousTextLayout",
            @"ConvertLF",
            @"ConvertToBackslash",
            @"ConvertToYen",
            @"CreateLabelList",
            @"CreateTagList",
            @"DarkModeInvertPreview",
            @"DefaultCommand",
            @"DefaultDarkTheme",
            @"DefaultEngine",
            @"DefaultLiteTheme",
            @"DefaultScript",
            @"DisplayAsBook",
            @"DistillerCommand",
            @"DockIconStyle",
            @"DocumentFont",
            @"DocumentFontAttributes",
            @"DocumentSplitWindowPosition",
            @"DocumentWindow",
            @"DocumentWindowFixedPosition",
            @"DocumentWindowPositionMode",
            @"EditorCanAddBrackets",
            @"Encoding",
            @"EncodingAutoDetection",
            @"EncodingMenuInSaveDialog",
            @"ExceptionListExcludesParameters",
            @"ExternalEditorTypesetAtStart",
            @"ExtraCommandsNotToCheckParameters",
            @"ExtraCommandsToCheckParameters",
            @"FindMethod",
            @"FlashBackgroundEnabled",
            @"FlashDelay",
            @"FlashFix",
            @"FullwidthSpaceCharacterKind",
            @"FullwidthSpaceCharacterKindExtended",
            @"GSBinPath",
            @"GlassMaxMagnification",
            @"HighlightContentEnabled",
            @"HtmlHome",
            @"HtmlWindowFixedPos",
            @"HtmlWindowName",
            @"HtmlWindowPosMode",
            @"IgnoreStartOnReboot",
            @"IncrementalSearch",
            @"IndexColorStart",
            @"InterpolationValue",
            @"KeepBackup",
            @"Kpsetool",
            @"LPanelOutlines",
            @"LastStyName",
            @"LatexCommand",
            @"LatexGSCommand",
            @"LatexPanel",
            @"LatexScriptCommand",
            @"LeftRightArrowsAlwaysPage",
            @"LineBreakMode",
            @"LineNumberEnabled",
            @"LineNumberSize",
            @"LinkPopups",
            @"MPanelOriginX",
            @"MPanelOriginY",
            @"MakeEmptyDocument",
            @"MakeatletterEnabled",
            @"MathExpressionCompletion",
            @"MiniaturizeRootFile",
            @"NSUserKeyEquivalents",
            @"NewLineCharacterKind",
            @"NewLineCharacterKindExtended",
            @"NoScrollEnabled",
            @"OpenAsTabs",
            @"OpenWithSourceInFront",
            @"OriginalSpelling",
            @"OtherEditorSync",
            @"OtherTeXExtensions",
            @"OtherTrashExtensions",
            @"PanelOriginX",
            @"PanelOriginY",
            @"ParensMatchingEnabled",
            @"PdfBack_A",
            @"PdfBack_B",
            @"PdfBack_G",
            @"PdfBack_R",
            @"PdfColorMap",
            @"PdfColorParam1",
            @"PdfColorParam2",
            @"PdfCopyType",
            @"PdfExportType",
            @"PdfFileRefresh",
            @"PdfFirstPageStyle",
            @"PdfFitSize",
            @"PdfFore_A",
            @"PdfFore_B",
            @"PdfFore_G",
            @"PdfFore_R",
            @"PdfKitFitSize",
            @"PdfKitMouseMode",
            @"PdfKitWindow",
            @"PdfMagnification",
            @"PdfMouseMode",
            @"PdfPageStyle",
            @"PdfQuickDrag",
            @"PdfRefresh",
            @"PdfWindow",
            @"PdfWindowFixedPosition",
            @"PdfWindowPositionMode",
            @"Pdfbackground_B",
            @"Pdfbackground_G",
            @"Pdfbackground_R",
            @"PortableDocumentWindowFixedPosition",
            @"PortablePdfWindowFixedPosition",
            @"PreviewDrawerOpen",
            @"PreviewWindowAlpha",
            @"RedConsoleAfterError",
            @"RefreshTime",
            @"ResetSourceTextColorEachTime",
            @"ReverseSyncBlue",
            @"ReverseSyncGreen",
            @"ReverseSyncRed",
            @"RightJustify",
            @"RightJustifyIfAny",
            @"SameFontForMacro",
            @"SaveDocumentFont",
            @"SavePSEnabled",
            @"SaveRelated",
            @"ShowFullPathEnabled",
            @"ShowFullwidthSpaceCharacter",
            @"ShowIndicatorForMoveEnabled",
            @"ShowInvisibleChractersEnabled",
            @"ShowNewLineCharacter",
            @"ShowSpaceCharacter",
            @"ShowSyncMarks",
            @"ShowTabCharacter",
            @"SmartInsertDelete",
            @"SourceAndPreviewInSameWindow",
            @"SourceFirstLineHeadIndent",
            @"SourceHeadIndent",
            @"SourceInterlineSpace",
            @"SourceWindowAlpha",
            @"SpaceCharacterKind",
            @"SpaceCharacterKindExtended",
            @"SparkleAutomaticUpdate",
            @"SparkleInterval",
            @"SpellCheckEnabled",
            @"SpellingAutomaticDefault",
            @"SpellingLanguageDefault",
            @"SwitchSides",
            @"SyncMethod",
            @"SyncUseTabs",
            @"SyntaxColorEntryLine",
            @"SyntaxColorFootnote",
            @"SyntaxColoringEnabled",
            @"TSHasBeenUsed",
            @"TSMenuShortcutOverrides",
            @"TSPreviewAppearanceMode",
            @"TabCharacterKind",
            @"TabCharacterKindExtended",
            @"TabIndent",
            @"TabsAlsoForInputFiles",
            @"TagMenuInMenuBar",
            @"TagSections",
            @"TeXAwareSpellChecking",
            @"TetexBinPath",
            @"TexCommand",
            @"TexGSCommand",
            @"TexScriptCommand",
            @"TextMateSync",
            @"TurnOffCommandSpellCheck",
            @"TurnOffCommentSpellCheck",
            @"TurnOffParameterSpellCheck",
            @"UseExternalEditor",
            @"UseNewTagsAndLabels",
            @"UseOldHeadingCommands",
            @"UseOutline",
            @"UseTransparency",
            @"UserInfoPath",
            @"WarnForShellEscape",
            @"WatchServer",
            @"XMLChapterTag",
            @"XMLConclusionTag",
            @"XMLExercisesTag",
            @"XMLFigureTag",
            @"XMLIntroductionTag",
            @"XMLMarkTag",
            @"XMLProjectTag",
            @"XMLSectionTag",
            @"XMLSubsectionTag",
            @"XMLSubsubsectionTag",
            @"XMLTableTag",
            @"backgroundAlpha",
            @"background_B",
            @"background_G",
            @"background_R",
            @"brieflyFlashYellowForMatch",
            @"commandblue",
            @"commandgreen",
            @"commandred",
            @"commentblue",
            @"commentgreen",
            @"commentred",
            @"expl3SyntaxColoring",
            @"foreground_B",
            @"foreground_G",
            @"foreground_R",
            @"fullscreenPageStyle",
            @"fullscreenResizeOption",
            @"highlightBracesBlue",
            @"highlightBracesGreen",
            @"highlightBracesRed",
            @"highlightContentBlue",
            @"highlightContentGreen",
            @"highlightContentRed",
            @"indexblue",
            @"indexgreen",
            @"indexred",
            @"insertionpoint_B",
            @"insertionpoint_G",
            @"insertionpoint_R",
            @"invisibleCharBlue",
            @"invisibleCharGreen",
            @"invisibleCharRed",
            @"markerblue",
            @"markergreen",
            @"markerred",
            @"matrixsize",
            @"ptexUtfOutput",
            @"syncWithRedOvals",
            @"tabs"
        ]];
    });
    return keys;
}

BOOL TSPreferenceProfilePreservesKey(NSString *key)
{
    if ([key hasPrefix:@"SU"] || [key hasPrefix:@"NSWindow Frame "] ||
        [key hasPrefix:@"NSToolbar Configuration "] || [key hasPrefix:@"NSSplitView Subview Frames "] ||
        [key hasPrefix:@"TSSettingsUI"]) return YES;
    return [@[
        @"AppleLanguages",
        @"ConsoleWindow",
        @"DocumentSplitWindowPosition",
        @"DocumentWindow",
        @"HtmlWindowName",
        @"LastStyName",
        @"LatexPanel",
        @"MPanelOriginX",
        @"MPanelOriginY",
        @"NSUserKeyEquivalents",
        @"PanelOriginX",
        @"PanelOriginY",
        @"PdfKitWindow",
        @"PdfWindow",
        @"SparkleAutomaticUpdate",
        @"SparkleInterval",
        @"TSMenuShortcutOverrides"
    ] containsObject:key];
}

@implementation TSPreferenceProfile
- (nullable instancetype)initWithProfile:(NSDictionary<NSString *, id> *)profile documentFont:(NSData *)fontData
{
    if (![profile isKindOfClass:NSDictionary.class] || fontData.length == 0) return nil;
    id path = profile[@"TetexBinPath"];
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
    updates[@"TSHasBeenUsed"] = @YES;
    updates[@"DocumentFont"] = fontData;
    [removals removeObject:@"TSHasBeenUsed"];
    [removals removeObject:@"DocumentFont"];
    // Reset attributed-font overrides alongside the standard document font.
    [updates removeObjectForKey:@"DocumentFontAttributes"];
    [removals addObject:@"DocumentFontAttributes"];
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
