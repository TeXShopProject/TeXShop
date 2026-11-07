// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceProfile.h"

static TSPreferenceKey const TSProfileKeyAcceptFirstMouse = @"AcceptFirstMouse";
static TSPreferenceKey const TSProfileKeyAggressiveTrashAUX = @"AggressiveTrashAUX";
static TSPreferenceKey const TSProfileKeyAltPath = @"AltPath";
static TSPreferenceKey const TSProfileKeyAlternateEngine = @"AlternateEngine";
static TSPreferenceKey const TSProfileKeyAlwaysHighlightEnabled = @"AlwaysHighlightEnabled";
static TSPreferenceKey const TSProfileKeyAntiAlias = @"AntiAlias";
static TSPreferenceKey const TSProfileKeyAppleLanguages = @"AppleLanguages";
static TSPreferenceKey const TSProfileKeyApplePersistence = @"ApplePersistence";
static TSPreferenceKey const TSProfileKeyAutoCompleteEnabled = @"AutoCompleteEnabled";
static TSPreferenceKey const TSProfileKeyAutoOpenRootFile = @"AutoOpenRootFile";
static TSPreferenceKey const TSProfileKeyAutoReloadExternalPDF = @"AutoReloadExternalPDF";
static TSPreferenceKey const TSProfileKeyAutoSaveEnabled = @"AutoSaveEnabled";
static TSPreferenceKey const TSProfileKeyAutomaticDashSubstitution = @"AutomaticDashSubstitution";
static TSPreferenceKey const TSProfileKeyAutomaticDataDetection = @"AutomaticDataDetection";
static TSPreferenceKey const TSProfileKeyAutomaticLinkDetection = @"AutomaticLinkDetection";
static TSPreferenceKey const TSProfileKeyAutomaticQuoteSubstitution = @"AutomaticQuoteSubstitution";
static TSPreferenceKey const TSProfileKeyAutomaticSpellingCorrectionEnabled = @"AutomaticSpellingCorrectionEnabled";
static TSPreferenceKey const TSProfileKeyAutomaticTextReplacement = @"AutomaticTextReplacement";
static TSPreferenceKey const TSProfileKeyAutomaticUTF8MACtoUTF8Conversion = @"AutomaticUTF8MACtoUTF8Conversion";
static TSPreferenceKey const TSProfileKeyBeepEnabled = @"BeepEnabled";
static TSPreferenceKey const TSProfileKeyBibDeskCompletion = @"BibDeskCompletion";
static TSPreferenceKey const TSProfileKeyBibTeXengine = @"BibTeXengine";
static TSPreferenceKey const TSProfileKeyBlockCursor = @"BlockCursor";
static TSPreferenceKey const TSProfileKeyBlockCursorB = @"BlockCursorB";
static TSPreferenceKey const TSProfileKeyBlockCursorG = @"BlockCursorG";
static TSPreferenceKey const TSProfileKeyBlockCursorR = @"BlockCursorR";
static TSPreferenceKey const TSProfileKeyBlockSide = @"BlockSide";
static TSPreferenceKey const TSProfileKeyBlockWidth = @"BlockWidth";
static TSPreferenceKey const TSProfileKeyBringFrontOnTypeset = @"BringFrontOnTypeset";
static TSPreferenceKey const TSProfileKeyBringPdfFrontOnAutomaticUpdate = @"BringPdfFrontOnAutomaticUpdate";
static TSPreferenceKey const TSProfileKeyBringPdfFrontOnTypeset = @"BringPdfFrontOnTypeset";
static TSPreferenceKey const TSProfileKeyCheckBraceEnabled = @"CheckBraceEnabled";
static TSPreferenceKey const TSProfileKeyCheckBracketEnabled = @"CheckBracketEnabled";
static TSPreferenceKey const TSProfileKeyCheckParenEnabled = @"CheckParenEnabled";
static TSPreferenceKey const TSProfileKeyCheckSquareBracketEnabled = @"CheckSquareBracketEnabled";
static TSPreferenceKey const TSProfileKeyColorImmediately = @"ColorImmediately";
static TSPreferenceKey const TSProfileKeyCommandCompletionAlternateMarkShortcut = @"CommandCompletionAlternateMarkShortcut";
static TSPreferenceKey const TSProfileKeyCommandCompletionChar = @"CommandCompletionChar";
static TSPreferenceKey const TSProfileKeyConTeXtTags = @"ConTeXtTags";
static TSPreferenceKey const TSProfileKeyConsoleBackgroundAlpha = @"ConsoleBackgroundAlpha";
static TSPreferenceKey const TSProfileKeyConsoleBackgroundColor_B = @"ConsoleBackgroundColor_B";
static TSPreferenceKey const TSProfileKeyConsoleBackgroundColor_G = @"ConsoleBackgroundColor_G";
static TSPreferenceKey const TSProfileKeyConsoleBackgroundColor_R = @"ConsoleBackgroundColor_R";
static TSPreferenceKey const TSProfileKeyConsoleBehavior = @"ConsoleBehavior";
static TSPreferenceKey const TSProfileKeyConsoleFontName = @"ConsoleFontName";
static TSPreferenceKey const TSProfileKeyConsoleFontSize = @"ConsoleFontSize";
static TSPreferenceKey const TSProfileKeyConsoleForegroundColor_B = @"ConsoleForegroundColor_B";
static TSPreferenceKey const TSProfileKeyConsoleForegroundColor_G = @"ConsoleForegroundColor_G";
static TSPreferenceKey const TSProfileKeyConsoleForegroundColor_R = @"ConsoleForegroundColor_R";
static TSPreferenceKey const TSProfileKeyConsoleWidthResize = @"ConsoleWidthResize";
static TSPreferenceKey const TSProfileKeyConsoleWindow = @"ConsoleWindow";
static TSPreferenceKey const TSProfileKeyConsoleWindowAlpha = @"ConsoleWindowAlpha";
static TSPreferenceKey const TSProfileKeyConsoleWindowFixedPos = @"ConsoleWindowFixedPos";
static TSPreferenceKey const TSProfileKeyConsoleWindowPosMode = @"ConsoleWindowPosMode";
static TSPreferenceKey const TSProfileKeyContiguousTextLayout = @"ContiguousTextLayout";
static TSPreferenceKey const TSProfileKeyConvertLF = @"ConvertLF";
static TSPreferenceKey const TSProfileKeyConvertToBackslash = @"ConvertToBackslash";
static TSPreferenceKey const TSProfileKeyConvertToYen = @"ConvertToYen";
static TSPreferenceKey const TSProfileKeyCreateLabelList = @"CreateLabelList";
static TSPreferenceKey const TSProfileKeyCreateTagList = @"CreateTagList";
static TSPreferenceKey const TSProfileKeyDarkModeInvertPreview = @"DarkModeInvertPreview";
static TSPreferenceKey const TSProfileKeyDefaultCommand = @"DefaultCommand";
static TSPreferenceKey const TSProfileKeyDefaultDarkTheme = @"DefaultDarkTheme";
static TSPreferenceKey const TSProfileKeyDefaultEngine = @"DefaultEngine";
static TSPreferenceKey const TSProfileKeyDefaultLiteTheme = @"DefaultLiteTheme";
static TSPreferenceKey const TSProfileKeyDefaultScript = @"DefaultScript";
static TSPreferenceKey const TSProfileKeyDisplayAsBook = @"DisplayAsBook";
static TSPreferenceKey const TSProfileKeyDistillerCommand = @"DistillerCommand";
static TSPreferenceKey const TSProfileKeyDockIconStyle = @"DockIconStyle";
static TSPreferenceKey const TSProfileKeyDocumentFont = @"DocumentFont";
static TSPreferenceKey const TSProfileKeyDocumentFontAttributes = @"DocumentFontAttributes";
static TSPreferenceKey const TSProfileKeyDocumentSplitWindowPosition = @"DocumentSplitWindowPosition";
static TSPreferenceKey const TSProfileKeyDocumentWindow = @"DocumentWindow";
static TSPreferenceKey const TSProfileKeyDocumentWindowFixedPosition = @"DocumentWindowFixedPosition";
static TSPreferenceKey const TSProfileKeyDocumentWindowPositionMode = @"DocumentWindowPositionMode";
static TSPreferenceKey const TSProfileKeyEditorCanAddBrackets = @"EditorCanAddBrackets";
static TSPreferenceKey const TSProfileKeyEncoding = @"Encoding";
static TSPreferenceKey const TSProfileKeyEncodingAutoDetection = @"EncodingAutoDetection";
static TSPreferenceKey const TSProfileKeyEncodingMenuInSaveDialog = @"EncodingMenuInSaveDialog";
static TSPreferenceKey const TSProfileKeyExceptionListExcludesParameters = @"ExceptionListExcludesParameters";
static TSPreferenceKey const TSProfileKeyExternalEditorTypesetAtStart = @"ExternalEditorTypesetAtStart";
static TSPreferenceKey const TSProfileKeyExtraCommandsNotToCheckParameters = @"ExtraCommandsNotToCheckParameters";
static TSPreferenceKey const TSProfileKeyExtraCommandsToCheckParameters = @"ExtraCommandsToCheckParameters";
static TSPreferenceKey const TSProfileKeyFindMethod = @"FindMethod";
static TSPreferenceKey const TSProfileKeyFlashBackgroundEnabled = @"FlashBackgroundEnabled";
static TSPreferenceKey const TSProfileKeyFlashDelay = @"FlashDelay";
static TSPreferenceKey const TSProfileKeyFlashFix = @"FlashFix";
static TSPreferenceKey const TSProfileKeyFullwidthSpaceCharacterKind = @"FullwidthSpaceCharacterKind";
static TSPreferenceKey const TSProfileKeyFullwidthSpaceCharacterKindExtended = @"FullwidthSpaceCharacterKindExtended";
static TSPreferenceKey const TSProfileKeyGSBinPath = @"GSBinPath";
static TSPreferenceKey const TSProfileKeyGlassMaxMagnification = @"GlassMaxMagnification";
static TSPreferenceKey const TSProfileKeyHighlightContentEnabled = @"HighlightContentEnabled";
static TSPreferenceKey const TSProfileKeyHtmlHome = @"HtmlHome";
static TSPreferenceKey const TSProfileKeyHtmlWindowFixedPos = @"HtmlWindowFixedPos";
static TSPreferenceKey const TSProfileKeyHtmlWindowName = @"HtmlWindowName";
static TSPreferenceKey const TSProfileKeyHtmlWindowPosMode = @"HtmlWindowPosMode";
static TSPreferenceKey const TSProfileKeyIgnoreStartOnReboot = @"IgnoreStartOnReboot";
static TSPreferenceKey const TSProfileKeyIncrementalSearch = @"IncrementalSearch";
static TSPreferenceKey const TSProfileKeyIndexColorStart = @"IndexColorStart";
static TSPreferenceKey const TSProfileKeyInterpolationValue = @"InterpolationValue";
static TSPreferenceKey const TSProfileKeyKeepBackup = @"KeepBackup";
static TSPreferenceKey const TSProfileKeyKpsetool = @"Kpsetool";
static TSPreferenceKey const TSProfileKeyLPanelOutlines = @"LPanelOutlines";
static TSPreferenceKey const TSProfileKeyLastStyName = @"LastStyName";
static TSPreferenceKey const TSProfileKeyLatexCommand = @"LatexCommand";
static TSPreferenceKey const TSProfileKeyLatexGSCommand = @"LatexGSCommand";
static TSPreferenceKey const TSProfileKeyLatexPanel = @"LatexPanel";
static TSPreferenceKey const TSProfileKeyLatexScriptCommand = @"LatexScriptCommand";
static TSPreferenceKey const TSProfileKeyLeftRightArrowsAlwaysPage = @"LeftRightArrowsAlwaysPage";
static TSPreferenceKey const TSProfileKeyLineBreakMode = @"LineBreakMode";
static TSPreferenceKey const TSProfileKeyLineNumberEnabled = @"LineNumberEnabled";
static TSPreferenceKey const TSProfileKeyLineNumberSize = @"LineNumberSize";
static TSPreferenceKey const TSProfileKeyLinkPopups = @"LinkPopups";
static TSPreferenceKey const TSProfileKeyMPanelOriginX = @"MPanelOriginX";
static TSPreferenceKey const TSProfileKeyMPanelOriginY = @"MPanelOriginY";
static TSPreferenceKey const TSProfileKeyMakeEmptyDocument = @"MakeEmptyDocument";
static TSPreferenceKey const TSProfileKeyMakeatletterEnabled = @"MakeatletterEnabled";
static TSPreferenceKey const TSProfileKeyMathExpressionCompletion = @"MathExpressionCompletion";
static TSPreferenceKey const TSProfileKeyMiniaturizeRootFile = @"MiniaturizeRootFile";
static TSPreferenceKey const TSProfileKeyNSUserKeyEquivalents = @"NSUserKeyEquivalents";
static TSPreferenceKey const TSProfileKeyNewLineCharacterKind = @"NewLineCharacterKind";
static TSPreferenceKey const TSProfileKeyNewLineCharacterKindExtended = @"NewLineCharacterKindExtended";
static TSPreferenceKey const TSProfileKeyNoScrollEnabled = @"NoScrollEnabled";
static TSPreferenceKey const TSProfileKeyOpenAsTabs = @"OpenAsTabs";
static TSPreferenceKey const TSProfileKeyOpenWithSourceInFront = @"OpenWithSourceInFront";
static TSPreferenceKey const TSProfileKeyOriginalSpelling = @"OriginalSpelling";
static TSPreferenceKey const TSProfileKeyOtherEditorSync = @"OtherEditorSync";
static TSPreferenceKey const TSProfileKeyOtherTeXExtensions = @"OtherTeXExtensions";
static TSPreferenceKey const TSProfileKeyOtherTrashExtensions = @"OtherTrashExtensions";
static TSPreferenceKey const TSProfileKeyPanelOriginX = @"PanelOriginX";
static TSPreferenceKey const TSProfileKeyPanelOriginY = @"PanelOriginY";
static TSPreferenceKey const TSProfileKeyParensMatchingEnabled = @"ParensMatchingEnabled";
static TSPreferenceKey const TSProfileKeyPdfBack_A = @"PdfBack_A";
static TSPreferenceKey const TSProfileKeyPdfBack_B = @"PdfBack_B";
static TSPreferenceKey const TSProfileKeyPdfBack_G = @"PdfBack_G";
static TSPreferenceKey const TSProfileKeyPdfBack_R = @"PdfBack_R";
static TSPreferenceKey const TSProfileKeyPdfColorMap = @"PdfColorMap";
static TSPreferenceKey const TSProfileKeyPdfColorParam1 = @"PdfColorParam1";
static TSPreferenceKey const TSProfileKeyPdfColorParam2 = @"PdfColorParam2";
static TSPreferenceKey const TSProfileKeyPdfCopyType = @"PdfCopyType";
static TSPreferenceKey const TSProfileKeyPdfExportType = @"PdfExportType";
static TSPreferenceKey const TSProfileKeyPdfFileRefresh = @"PdfFileRefresh";
static TSPreferenceKey const TSProfileKeyPdfFirstPageStyle = @"PdfFirstPageStyle";
static TSPreferenceKey const TSProfileKeyPdfFitSize = @"PdfFitSize";
static TSPreferenceKey const TSProfileKeyPdfFore_A = @"PdfFore_A";
static TSPreferenceKey const TSProfileKeyPdfFore_B = @"PdfFore_B";
static TSPreferenceKey const TSProfileKeyPdfFore_G = @"PdfFore_G";
static TSPreferenceKey const TSProfileKeyPdfFore_R = @"PdfFore_R";
static TSPreferenceKey const TSProfileKeyPdfKitFitSize = @"PdfKitFitSize";
static TSPreferenceKey const TSProfileKeyPdfKitMouseMode = @"PdfKitMouseMode";
static TSPreferenceKey const TSProfileKeyPdfKitWindow = @"PdfKitWindow";
static TSPreferenceKey const TSProfileKeyPdfMagnification = @"PdfMagnification";
static TSPreferenceKey const TSProfileKeyPdfMouseMode = @"PdfMouseMode";
static TSPreferenceKey const TSProfileKeyPdfPageStyle = @"PdfPageStyle";
static TSPreferenceKey const TSProfileKeyPdfQuickDrag = @"PdfQuickDrag";
static TSPreferenceKey const TSProfileKeyPdfRefresh = @"PdfRefresh";
static TSPreferenceKey const TSProfileKeyPdfWindow = @"PdfWindow";
static TSPreferenceKey const TSProfileKeyPdfWindowFixedPosition = @"PdfWindowFixedPosition";
static TSPreferenceKey const TSProfileKeyPdfWindowPositionMode = @"PdfWindowPositionMode";
static TSPreferenceKey const TSProfileKeyPdfbackground_B = @"Pdfbackground_B";
static TSPreferenceKey const TSProfileKeyPdfbackground_G = @"Pdfbackground_G";
static TSPreferenceKey const TSProfileKeyPdfbackground_R = @"Pdfbackground_R";
static TSPreferenceKey const TSProfileKeyPortableDocumentWindowFixedPosition = @"PortableDocumentWindowFixedPosition";
static TSPreferenceKey const TSProfileKeyPortablePdfWindowFixedPosition = @"PortablePdfWindowFixedPosition";
static TSPreferenceKey const TSProfileKeyPreviewDrawerOpen = @"PreviewDrawerOpen";
static TSPreferenceKey const TSProfileKeyPreviewWindowAlpha = @"PreviewWindowAlpha";
static TSPreferenceKey const TSProfileKeyRedConsoleAfterError = @"RedConsoleAfterError";
static TSPreferenceKey const TSProfileKeyRefreshTime = @"RefreshTime";
static TSPreferenceKey const TSProfileKeyResetSourceTextColorEachTime = @"ResetSourceTextColorEachTime";
static TSPreferenceKey const TSProfileKeyReverseSyncBlue = @"ReverseSyncBlue";
static TSPreferenceKey const TSProfileKeyReverseSyncGreen = @"ReverseSyncGreen";
static TSPreferenceKey const TSProfileKeyReverseSyncRed = @"ReverseSyncRed";
static TSPreferenceKey const TSProfileKeyRightJustify = @"RightJustify";
static TSPreferenceKey const TSProfileKeyRightJustifyIfAny = @"RightJustifyIfAny";
static TSPreferenceKey const TSProfileKeySameFontForMacro = @"SameFontForMacro";
static TSPreferenceKey const TSProfileKeySaveDocumentFont = @"SaveDocumentFont";
static TSPreferenceKey const TSProfileKeySavePSEnabled = @"SavePSEnabled";
static TSPreferenceKey const TSProfileKeySaveRelated = @"SaveRelated";
static TSPreferenceKey const TSProfileKeyShowFullPathEnabled = @"ShowFullPathEnabled";
static TSPreferenceKey const TSProfileKeyShowFullwidthSpaceCharacter = @"ShowFullwidthSpaceCharacter";
static TSPreferenceKey const TSProfileKeyShowIndicatorForMoveEnabled = @"ShowIndicatorForMoveEnabled";
static TSPreferenceKey const TSProfileKeyShowInvisibleChractersEnabled = @"ShowInvisibleChractersEnabled";
static TSPreferenceKey const TSProfileKeyShowNewLineCharacter = @"ShowNewLineCharacter";
static TSPreferenceKey const TSProfileKeyShowSpaceCharacter = @"ShowSpaceCharacter";
static TSPreferenceKey const TSProfileKeyShowSyncMarks = @"ShowSyncMarks";
static TSPreferenceKey const TSProfileKeyShowTabCharacter = @"ShowTabCharacter";
static TSPreferenceKey const TSProfileKeySmartInsertDelete = @"SmartInsertDelete";
static TSPreferenceKey const TSProfileKeySourceAndPreviewInSameWindow = @"SourceAndPreviewInSameWindow";
static TSPreferenceKey const TSProfileKeySourceFirstLineHeadIndent = @"SourceFirstLineHeadIndent";
static TSPreferenceKey const TSProfileKeySourceHeadIndent = @"SourceHeadIndent";
static TSPreferenceKey const TSProfileKeySourceInterlineSpace = @"SourceInterlineSpace";
static TSPreferenceKey const TSProfileKeySourceWindowAlpha = @"SourceWindowAlpha";
static TSPreferenceKey const TSProfileKeySpaceCharacterKind = @"SpaceCharacterKind";
static TSPreferenceKey const TSProfileKeySpaceCharacterKindExtended = @"SpaceCharacterKindExtended";
static TSPreferenceKey const TSProfileKeySparkleAutomaticUpdate = @"SparkleAutomaticUpdate";
static TSPreferenceKey const TSProfileKeySparkleInterval = @"SparkleInterval";
static TSPreferenceKey const TSProfileKeySpellCheckEnabled = @"SpellCheckEnabled";
static TSPreferenceKey const TSProfileKeySpellingAutomaticDefault = @"SpellingAutomaticDefault";
static TSPreferenceKey const TSProfileKeySpellingLanguageDefault = @"SpellingLanguageDefault";
static TSPreferenceKey const TSProfileKeySwitchSides = @"SwitchSides";
static TSPreferenceKey const TSProfileKeySyncMethod = @"SyncMethod";
static TSPreferenceKey const TSProfileKeySyncUseTabs = @"SyncUseTabs";
static TSPreferenceKey const TSProfileKeySyntaxColorEntryLine = @"SyntaxColorEntryLine";
static TSPreferenceKey const TSProfileKeySyntaxColorFootnote = @"SyntaxColorFootnote";
static TSPreferenceKey const TSProfileKeySyntaxColoringEnabled = @"SyntaxColoringEnabled";
static TSPreferenceKey const TSProfileKeyTSHasBeenUsed = @"TSHasBeenUsed";
static TSPreferenceKey const TSProfileKeyTSMenuShortcutOverrides = @"TSMenuShortcutOverrides";
static TSPreferenceKey const TSProfileKeyTSPreviewAppearanceMode = @"TSPreviewAppearanceMode";
static TSPreferenceKey const TSProfileKeyTabCharacterKind = @"TabCharacterKind";
static TSPreferenceKey const TSProfileKeyTabCharacterKindExtended = @"TabCharacterKindExtended";
static TSPreferenceKey const TSProfileKeyTabIndent = @"TabIndent";
static TSPreferenceKey const TSProfileKeyTabsAlsoForInputFiles = @"TabsAlsoForInputFiles";
static TSPreferenceKey const TSProfileKeyTagMenuInMenuBar = @"TagMenuInMenuBar";
static TSPreferenceKey const TSProfileKeyTagSections = @"TagSections";
static TSPreferenceKey const TSProfileKeyTeXAwareSpellChecking = @"TeXAwareSpellChecking";
static TSPreferenceKey const TSProfileKeyTetexBinPath = @"TetexBinPath";
static TSPreferenceKey const TSProfileKeyTexCommand = @"TexCommand";
static TSPreferenceKey const TSProfileKeyTexGSCommand = @"TexGSCommand";
static TSPreferenceKey const TSProfileKeyTexScriptCommand = @"TexScriptCommand";
static TSPreferenceKey const TSProfileKeyTextMateSync = @"TextMateSync";
static TSPreferenceKey const TSProfileKeyTurnOffCommandSpellCheck = @"TurnOffCommandSpellCheck";
static TSPreferenceKey const TSProfileKeyTurnOffCommentSpellCheck = @"TurnOffCommentSpellCheck";
static TSPreferenceKey const TSProfileKeyTurnOffParameterSpellCheck = @"TurnOffParameterSpellCheck";
static TSPreferenceKey const TSProfileKeyUseExternalEditor = @"UseExternalEditor";
static TSPreferenceKey const TSProfileKeyUseNewTagsAndLabels = @"UseNewTagsAndLabels";
static TSPreferenceKey const TSProfileKeyUseOldHeadingCommands = @"UseOldHeadingCommands";
static TSPreferenceKey const TSProfileKeyUseOutline = @"UseOutline";
static TSPreferenceKey const TSProfileKeyUseTransparency = @"UseTransparency";
static TSPreferenceKey const TSProfileKeyUserInfoPath = @"UserInfoPath";
static TSPreferenceKey const TSProfileKeyWarnForShellEscape = @"WarnForShellEscape";
static TSPreferenceKey const TSProfileKeyWatchServer = @"WatchServer";
static TSPreferenceKey const TSProfileKeyXMLChapterTag = @"XMLChapterTag";
static TSPreferenceKey const TSProfileKeyXMLConclusionTag = @"XMLConclusionTag";
static TSPreferenceKey const TSProfileKeyXMLExercisesTag = @"XMLExercisesTag";
static TSPreferenceKey const TSProfileKeyXMLFigureTag = @"XMLFigureTag";
static TSPreferenceKey const TSProfileKeyXMLIntroductionTag = @"XMLIntroductionTag";
static TSPreferenceKey const TSProfileKeyXMLMarkTag = @"XMLMarkTag";
static TSPreferenceKey const TSProfileKeyXMLProjectTag = @"XMLProjectTag";
static TSPreferenceKey const TSProfileKeyXMLSectionTag = @"XMLSectionTag";
static TSPreferenceKey const TSProfileKeyXMLSubsectionTag = @"XMLSubsectionTag";
static TSPreferenceKey const TSProfileKeyXMLSubsubsectionTag = @"XMLSubsubsectionTag";
static TSPreferenceKey const TSProfileKeyXMLTableTag = @"XMLTableTag";
static TSPreferenceKey const TSProfileKeybackgroundAlpha = @"backgroundAlpha";
static TSPreferenceKey const TSProfileKeybackground_B = @"background_B";
static TSPreferenceKey const TSProfileKeybackground_G = @"background_G";
static TSPreferenceKey const TSProfileKeybackground_R = @"background_R";
static TSPreferenceKey const TSProfileKeybrieflyFlashYellowForMatch = @"brieflyFlashYellowForMatch";
static TSPreferenceKey const TSProfileKeycommandblue = @"commandblue";
static TSPreferenceKey const TSProfileKeycommandgreen = @"commandgreen";
static TSPreferenceKey const TSProfileKeycommandred = @"commandred";
static TSPreferenceKey const TSProfileKeycommentblue = @"commentblue";
static TSPreferenceKey const TSProfileKeycommentgreen = @"commentgreen";
static TSPreferenceKey const TSProfileKeycommentred = @"commentred";
static TSPreferenceKey const TSProfileKeyexpl3SyntaxColoring = @"expl3SyntaxColoring";
static TSPreferenceKey const TSProfileKeyforeground_B = @"foreground_B";
static TSPreferenceKey const TSProfileKeyforeground_G = @"foreground_G";
static TSPreferenceKey const TSProfileKeyforeground_R = @"foreground_R";
static TSPreferenceKey const TSProfileKeyfullscreenPageStyle = @"fullscreenPageStyle";
static TSPreferenceKey const TSProfileKeyfullscreenResizeOption = @"fullscreenResizeOption";
static TSPreferenceKey const TSProfileKeyhighlightBracesBlue = @"highlightBracesBlue";
static TSPreferenceKey const TSProfileKeyhighlightBracesGreen = @"highlightBracesGreen";
static TSPreferenceKey const TSProfileKeyhighlightBracesRed = @"highlightBracesRed";
static TSPreferenceKey const TSProfileKeyhighlightContentBlue = @"highlightContentBlue";
static TSPreferenceKey const TSProfileKeyhighlightContentGreen = @"highlightContentGreen";
static TSPreferenceKey const TSProfileKeyhighlightContentRed = @"highlightContentRed";
static TSPreferenceKey const TSProfileKeyindexblue = @"indexblue";
static TSPreferenceKey const TSProfileKeyindexgreen = @"indexgreen";
static TSPreferenceKey const TSProfileKeyindexred = @"indexred";
static TSPreferenceKey const TSProfileKeyinsertionpoint_B = @"insertionpoint_B";
static TSPreferenceKey const TSProfileKeyinsertionpoint_G = @"insertionpoint_G";
static TSPreferenceKey const TSProfileKeyinsertionpoint_R = @"insertionpoint_R";
static TSPreferenceKey const TSProfileKeyinvisibleCharBlue = @"invisibleCharBlue";
static TSPreferenceKey const TSProfileKeyinvisibleCharGreen = @"invisibleCharGreen";
static TSPreferenceKey const TSProfileKeyinvisibleCharRed = @"invisibleCharRed";
static TSPreferenceKey const TSProfileKeymarkerblue = @"markerblue";
static TSPreferenceKey const TSProfileKeymarkergreen = @"markergreen";
static TSPreferenceKey const TSProfileKeymarkerred = @"markerred";
static TSPreferenceKey const TSProfileKeymatrixsize = @"matrixsize";
static TSPreferenceKey const TSProfileKeyptexUtfOutput = @"ptexUtfOutput";
static TSPreferenceKey const TSProfileKeysyncWithRedOvals = @"syncWithRedOvals";
static TSPreferenceKey const TSProfileKeytabs = @"tabs";

static NSUInteger profileApplicationDepth;
BOOL TSPreferenceProfileIsApplying(void) { return profileApplicationDepth != 0; }
NSSet<TSPreferenceKey> *TSKnownPreferenceKeys(void)
{
    static NSSet<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[
            TSProfileKeyAcceptFirstMouse,
            TSProfileKeyAggressiveTrashAUX,
            TSProfileKeyAltPath,
            TSProfileKeyAlternateEngine,
            TSProfileKeyAlwaysHighlightEnabled,
            TSProfileKeyAntiAlias,
            TSProfileKeyAppleLanguages,
            TSProfileKeyApplePersistence,
            TSProfileKeyAutoCompleteEnabled,
            TSProfileKeyAutoOpenRootFile,
            TSProfileKeyAutoReloadExternalPDF,
            TSProfileKeyAutoSaveEnabled,
            TSProfileKeyAutomaticDashSubstitution,
            TSProfileKeyAutomaticDataDetection,
            TSProfileKeyAutomaticLinkDetection,
            TSProfileKeyAutomaticQuoteSubstitution,
            TSProfileKeyAutomaticSpellingCorrectionEnabled,
            TSProfileKeyAutomaticTextReplacement,
            TSProfileKeyAutomaticUTF8MACtoUTF8Conversion,
            TSProfileKeyBeepEnabled,
            TSProfileKeyBibDeskCompletion,
            TSProfileKeyBibTeXengine,
            TSProfileKeyBlockCursor,
            TSProfileKeyBlockCursorB,
            TSProfileKeyBlockCursorG,
            TSProfileKeyBlockCursorR,
            TSProfileKeyBlockSide,
            TSProfileKeyBlockWidth,
            TSProfileKeyBringFrontOnTypeset,
            TSProfileKeyBringPdfFrontOnAutomaticUpdate,
            TSProfileKeyBringPdfFrontOnTypeset,
            TSProfileKeyCheckBraceEnabled,
            TSProfileKeyCheckBracketEnabled,
            TSProfileKeyCheckParenEnabled,
            TSProfileKeyCheckSquareBracketEnabled,
            TSProfileKeyColorImmediately,
            TSProfileKeyCommandCompletionAlternateMarkShortcut,
            TSProfileKeyCommandCompletionChar,
            TSProfileKeyConTeXtTags,
            TSProfileKeyConsoleBackgroundAlpha,
            TSProfileKeyConsoleBackgroundColor_B,
            TSProfileKeyConsoleBackgroundColor_G,
            TSProfileKeyConsoleBackgroundColor_R,
            TSProfileKeyConsoleBehavior,
            TSProfileKeyConsoleFontName,
            TSProfileKeyConsoleFontSize,
            TSProfileKeyConsoleForegroundColor_B,
            TSProfileKeyConsoleForegroundColor_G,
            TSProfileKeyConsoleForegroundColor_R,
            TSProfileKeyConsoleWidthResize,
            TSProfileKeyConsoleWindow,
            TSProfileKeyConsoleWindowAlpha,
            TSProfileKeyConsoleWindowFixedPos,
            TSProfileKeyConsoleWindowPosMode,
            TSProfileKeyContiguousTextLayout,
            TSProfileKeyConvertLF,
            TSProfileKeyConvertToBackslash,
            TSProfileKeyConvertToYen,
            TSProfileKeyCreateLabelList,
            TSProfileKeyCreateTagList,
            TSProfileKeyDarkModeInvertPreview,
            TSProfileKeyDefaultCommand,
            TSProfileKeyDefaultDarkTheme,
            TSProfileKeyDefaultEngine,
            TSProfileKeyDefaultLiteTheme,
            TSProfileKeyDefaultScript,
            TSProfileKeyDisplayAsBook,
            TSProfileKeyDistillerCommand,
            TSProfileKeyDockIconStyle,
            TSProfileKeyDocumentFont,
            TSProfileKeyDocumentFontAttributes,
            TSProfileKeyDocumentSplitWindowPosition,
            TSProfileKeyDocumentWindow,
            TSProfileKeyDocumentWindowFixedPosition,
            TSProfileKeyDocumentWindowPositionMode,
            TSProfileKeyEditorCanAddBrackets,
            TSProfileKeyEncoding,
            TSProfileKeyEncodingAutoDetection,
            TSProfileKeyEncodingMenuInSaveDialog,
            TSProfileKeyExceptionListExcludesParameters,
            TSProfileKeyExternalEditorTypesetAtStart,
            TSProfileKeyExtraCommandsNotToCheckParameters,
            TSProfileKeyExtraCommandsToCheckParameters,
            TSProfileKeyFindMethod,
            TSProfileKeyFlashBackgroundEnabled,
            TSProfileKeyFlashDelay,
            TSProfileKeyFlashFix,
            TSProfileKeyFullwidthSpaceCharacterKind,
            TSProfileKeyFullwidthSpaceCharacterKindExtended,
            TSProfileKeyGSBinPath,
            TSProfileKeyGlassMaxMagnification,
            TSProfileKeyHighlightContentEnabled,
            TSProfileKeyHtmlHome,
            TSProfileKeyHtmlWindowFixedPos,
            TSProfileKeyHtmlWindowName,
            TSProfileKeyHtmlWindowPosMode,
            TSProfileKeyIgnoreStartOnReboot,
            TSProfileKeyIncrementalSearch,
            TSProfileKeyIndexColorStart,
            TSProfileKeyInterpolationValue,
            TSProfileKeyKeepBackup,
            TSProfileKeyKpsetool,
            TSProfileKeyLPanelOutlines,
            TSProfileKeyLastStyName,
            TSProfileKeyLatexCommand,
            TSProfileKeyLatexGSCommand,
            TSProfileKeyLatexPanel,
            TSProfileKeyLatexScriptCommand,
            TSProfileKeyLeftRightArrowsAlwaysPage,
            TSProfileKeyLineBreakMode,
            TSProfileKeyLineNumberEnabled,
            TSProfileKeyLineNumberSize,
            TSProfileKeyLinkPopups,
            TSProfileKeyMPanelOriginX,
            TSProfileKeyMPanelOriginY,
            TSProfileKeyMakeEmptyDocument,
            TSProfileKeyMakeatletterEnabled,
            TSProfileKeyMathExpressionCompletion,
            TSProfileKeyMiniaturizeRootFile,
            TSProfileKeyNSUserKeyEquivalents,
            TSProfileKeyNewLineCharacterKind,
            TSProfileKeyNewLineCharacterKindExtended,
            TSProfileKeyNoScrollEnabled,
            TSProfileKeyOpenAsTabs,
            TSProfileKeyOpenWithSourceInFront,
            TSProfileKeyOriginalSpelling,
            TSProfileKeyOtherEditorSync,
            TSProfileKeyOtherTeXExtensions,
            TSProfileKeyOtherTrashExtensions,
            TSProfileKeyPanelOriginX,
            TSProfileKeyPanelOriginY,
            TSProfileKeyParensMatchingEnabled,
            TSProfileKeyPdfBack_A,
            TSProfileKeyPdfBack_B,
            TSProfileKeyPdfBack_G,
            TSProfileKeyPdfBack_R,
            TSProfileKeyPdfColorMap,
            TSProfileKeyPdfColorParam1,
            TSProfileKeyPdfColorParam2,
            TSProfileKeyPdfCopyType,
            TSProfileKeyPdfExportType,
            TSProfileKeyPdfFileRefresh,
            TSProfileKeyPdfFirstPageStyle,
            TSProfileKeyPdfFitSize,
            TSProfileKeyPdfFore_A,
            TSProfileKeyPdfFore_B,
            TSProfileKeyPdfFore_G,
            TSProfileKeyPdfFore_R,
            TSProfileKeyPdfKitFitSize,
            TSProfileKeyPdfKitMouseMode,
            TSProfileKeyPdfKitWindow,
            TSProfileKeyPdfMagnification,
            TSProfileKeyPdfMouseMode,
            TSProfileKeyPdfPageStyle,
            TSProfileKeyPdfQuickDrag,
            TSProfileKeyPdfRefresh,
            TSProfileKeyPdfWindow,
            TSProfileKeyPdfWindowFixedPosition,
            TSProfileKeyPdfWindowPositionMode,
            TSProfileKeyPdfbackground_B,
            TSProfileKeyPdfbackground_G,
            TSProfileKeyPdfbackground_R,
            TSProfileKeyPortableDocumentWindowFixedPosition,
            TSProfileKeyPortablePdfWindowFixedPosition,
            TSProfileKeyPreviewDrawerOpen,
            TSProfileKeyPreviewWindowAlpha,
            TSProfileKeyRedConsoleAfterError,
            TSProfileKeyRefreshTime,
            TSProfileKeyResetSourceTextColorEachTime,
            TSProfileKeyReverseSyncBlue,
            TSProfileKeyReverseSyncGreen,
            TSProfileKeyReverseSyncRed,
            TSProfileKeyRightJustify,
            TSProfileKeyRightJustifyIfAny,
            TSProfileKeySameFontForMacro,
            TSProfileKeySaveDocumentFont,
            TSProfileKeySavePSEnabled,
            TSProfileKeySaveRelated,
            TSProfileKeyShowFullPathEnabled,
            TSProfileKeyShowFullwidthSpaceCharacter,
            TSProfileKeyShowIndicatorForMoveEnabled,
            TSProfileKeyShowInvisibleChractersEnabled,
            TSProfileKeyShowNewLineCharacter,
            TSProfileKeyShowSpaceCharacter,
            TSProfileKeyShowSyncMarks,
            TSProfileKeyShowTabCharacter,
            TSProfileKeySmartInsertDelete,
            TSProfileKeySourceAndPreviewInSameWindow,
            TSProfileKeySourceFirstLineHeadIndent,
            TSProfileKeySourceHeadIndent,
            TSProfileKeySourceInterlineSpace,
            TSProfileKeySourceWindowAlpha,
            TSProfileKeySpaceCharacterKind,
            TSProfileKeySpaceCharacterKindExtended,
            TSProfileKeySparkleAutomaticUpdate,
            TSProfileKeySparkleInterval,
            TSProfileKeySpellCheckEnabled,
            TSProfileKeySpellingAutomaticDefault,
            TSProfileKeySpellingLanguageDefault,
            TSProfileKeySwitchSides,
            TSProfileKeySyncMethod,
            TSProfileKeySyncUseTabs,
            TSProfileKeySyntaxColorEntryLine,
            TSProfileKeySyntaxColorFootnote,
            TSProfileKeySyntaxColoringEnabled,
            TSProfileKeyTSHasBeenUsed,
            TSProfileKeyTSMenuShortcutOverrides,
            TSProfileKeyTSPreviewAppearanceMode,
            TSProfileKeyTabCharacterKind,
            TSProfileKeyTabCharacterKindExtended,
            TSProfileKeyTabIndent,
            TSProfileKeyTabsAlsoForInputFiles,
            TSProfileKeyTagMenuInMenuBar,
            TSProfileKeyTagSections,
            TSProfileKeyTeXAwareSpellChecking,
            TSProfileKeyTetexBinPath,
            TSProfileKeyTexCommand,
            TSProfileKeyTexGSCommand,
            TSProfileKeyTexScriptCommand,
            TSProfileKeyTextMateSync,
            TSProfileKeyTurnOffCommandSpellCheck,
            TSProfileKeyTurnOffCommentSpellCheck,
            TSProfileKeyTurnOffParameterSpellCheck,
            TSProfileKeyUseExternalEditor,
            TSProfileKeyUseNewTagsAndLabels,
            TSProfileKeyUseOldHeadingCommands,
            TSProfileKeyUseOutline,
            TSProfileKeyUseTransparency,
            TSProfileKeyUserInfoPath,
            TSProfileKeyWarnForShellEscape,
            TSProfileKeyWatchServer,
            TSProfileKeyXMLChapterTag,
            TSProfileKeyXMLConclusionTag,
            TSProfileKeyXMLExercisesTag,
            TSProfileKeyXMLFigureTag,
            TSProfileKeyXMLIntroductionTag,
            TSProfileKeyXMLMarkTag,
            TSProfileKeyXMLProjectTag,
            TSProfileKeyXMLSectionTag,
            TSProfileKeyXMLSubsectionTag,
            TSProfileKeyXMLSubsubsectionTag,
            TSProfileKeyXMLTableTag,
            TSProfileKeybackgroundAlpha,
            TSProfileKeybackground_B,
            TSProfileKeybackground_G,
            TSProfileKeybackground_R,
            TSProfileKeybrieflyFlashYellowForMatch,
            TSProfileKeycommandblue,
            TSProfileKeycommandgreen,
            TSProfileKeycommandred,
            TSProfileKeycommentblue,
            TSProfileKeycommentgreen,
            TSProfileKeycommentred,
            TSProfileKeyexpl3SyntaxColoring,
            TSProfileKeyforeground_B,
            TSProfileKeyforeground_G,
            TSProfileKeyforeground_R,
            TSProfileKeyfullscreenPageStyle,
            TSProfileKeyfullscreenResizeOption,
            TSProfileKeyhighlightBracesBlue,
            TSProfileKeyhighlightBracesGreen,
            TSProfileKeyhighlightBracesRed,
            TSProfileKeyhighlightContentBlue,
            TSProfileKeyhighlightContentGreen,
            TSProfileKeyhighlightContentRed,
            TSProfileKeyindexblue,
            TSProfileKeyindexgreen,
            TSProfileKeyindexred,
            TSProfileKeyinsertionpoint_B,
            TSProfileKeyinsertionpoint_G,
            TSProfileKeyinsertionpoint_R,
            TSProfileKeyinvisibleCharBlue,
            TSProfileKeyinvisibleCharGreen,
            TSProfileKeyinvisibleCharRed,
            TSProfileKeymarkerblue,
            TSProfileKeymarkergreen,
            TSProfileKeymarkerred,
            TSProfileKeymatrixsize,
            TSProfileKeyptexUtfOutput,
            TSProfileKeysyncWithRedOvals,
            TSProfileKeytabs
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
        TSProfileKeyConsoleWindow,
        TSProfileKeyDocumentSplitWindowPosition,
        TSProfileKeyDocumentWindow,
        TSProfileKeyHtmlWindowName,
        TSProfileKeyLastStyName,
        TSProfileKeyLatexPanel,
        TSProfileKeyMPanelOriginX,
        TSProfileKeyMPanelOriginY,
        TSProfileKeyNSUserKeyEquivalents,
        TSProfileKeyPanelOriginX,
        TSProfileKeyPanelOriginY,
        TSProfileKeyPdfKitWindow,
        TSProfileKeyPdfWindow,
        TSProfileKeySparkleAutomaticUpdate,
        TSProfileKeySparkleInterval,
        TSProfileKeyTSMenuShortcutOverrides
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
    id path = profile[TSProfileKeyTetexBinPath];
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
    updates[TSProfileKeyTSHasBeenUsed] = @YES;
    updates[TSProfileKeyDocumentFont] = fontData;
    [removals removeObject:TSProfileKeyTSHasBeenUsed];
    [removals removeObject:TSProfileKeyDocumentFont];
    // Reset attributed-font overrides alongside the standard document font.
    [updates removeObjectForKey:TSProfileKeyDocumentFontAttributes];
    [removals addObject:TSProfileKeyDocumentFontAttributes];
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
