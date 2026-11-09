// SPDX-License-Identifier: GPL-2.0-or-later
// Category-owned display refresh; original nib outlets remain compatibility adapters.
- (void)refreshGeneralSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [_sourceWindowPosMatrix selectCellWithTag:[defaults integerForKey:DocumentWindowPosModeKey]];
    if ([defaults integerForKey:DocumentWindowPosModeKey] == 0)
        [_docWindowPosButton setEnabled:YES];
    else
        [_docWindowPosButton setEnabled:NO];
    [_openEmptyButton setState:[defaults boolForKey:MakeEmptyDocumentKey]];
    [_externalEditorButton setState:[defaults boolForKey:UseExternalEditorKey]];
    [_openRootFileButton setState:[defaults boolForKey:AutoOpenRootFileKey]];
    [_miniaturizeRootFileButton setState:[defaults boolForKey:MiniaturizeRootFileKey]];
    useOneWindowButton.state = [defaults boolForKey:SourceAndPreviewInSameWindowKey];
    useTwoWindowsButton.state = ![defaults boolForKey:SourceAndPreviewInSameWindowKey];
    useRightSourceButton.state = [defaults boolForKey:SwitchSidesKey];
    useLeftSourceButton.state = ![defaults boolForKey:SwitchSidesKey];
    [_openAsTabsMatrix selectItemWithTag:[defaults integerForKey:OpenAsTabsKey]];
    [_consoleWindowPosMatrix selectCellWithTag:[defaults integerForKey:ConsoleWindowPosModeKey]];
    if ([defaults integerForKey:ConsoleWindowPosModeKey] == 0)
        [_consoleWindowPosButton setEnabled:YES];
    else
        [_consoleWindowPosButton setEnabled:NO];
    [_pdfWindowPosMatrix selectCellWithTag:[defaults integerForKey:PdfWindowPosModeKey]];
    if ([defaults integerForKey:PdfWindowPosModeKey] == 0)
        [_pdfWindowPosButton setEnabled:YES];
    else
        [_pdfWindowPosButton setEnabled:NO];
    [_htmlWindowPosMatrix selectCellWithTag:[defaults integerForKey:HtmlWindowPosModeKey]];
    if ([defaults integerForKey:HtmlWindowPosModeKey] == 0)
        [_htmlWindowPosButton setEnabled:YES];
    else
        [_htmlWindowPosButton setEnabled:NO];
    [self setSettingsControl:useLeftSourceButton enabled:YES];
    [self setSettingsControl:useRightSourceButton enabled:YES];
}

- (void)refreshDocumentsSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [_convertUTFButton setState:[defaults boolForKey:AutomaticUTF8MACtoUTF8ConversionKey]];
    [_autoSaveEnabledButton setState:[defaults boolForKey:AutoSaveEnabledKey]];
    [_keepBackupButton setState:[defaults boolForKey:KeepBackupKey]];
    _keepBackupButton.enabled = ![defaults boolForKey:AutoSaveEnabledKey];
    [_saveEncodingMenuButton setState:[defaults boolForKey:EncodingMenuInSaveDialogKey]];
    [_defaultEncodeMatrix removeAllItems];
    [[TSEncodingSupport sharedInstance] addEncodingsToMenu:[_defaultEncodeMatrix menu] withTarget:0 action:0];
    [_defaultEncodeMatrix selectItemWithTag:[[TSEncodingSupport sharedInstance] defaultEncoding]];
    [_saveRelatedButton setState:[defaults boolForKey:SaveRelatedKey]];
    [self setSettingsControl:_keepBackupButton enabled:![defaults boolForKey:AutoSaveEnabledKey]];
}

- (void)refreshEditorSettingsFromDefaults:(NSUserDefaults *)defaults
{
    NSData *fontData, *attributesData;
    NSInteger tabSize;
    NSNumber *myNumber;
    fontData = [defaults objectForKey:DocumentFontKey];
    if (fontData != nil)
    {
        self.documentFont = [NSUnarchiver unarchiveObjectWithData:fontData];
    }
    self.fontAttributes = nil;
    attributesData = [defaults objectForKey:DocumentFontAttributesKey];
    if (attributesData != nil)
    {
        self.fontAttributes = [NSUnarchiver unarchiveObjectWithData:attributesData];
    }
    [self updateDocumentFontTextField];
    [_tabIndentButton setState:[defaults boolForKey:TabIndentKey]];
    [_syntaxColorLineButton setState:[defaults boolForKey:SyntaxColorEntryLineKey]];
    [_syntaxColorButton setState:[defaults boolForKey:SyntaxColoringEnabledKey]];
    [_selectActivateButton setState:[defaults boolForKey:AcceptFirstMouseKey]];
    [_parensMatchButton setState:[defaults boolForKey:ParensMatchingEnabledKey]];
    [_editorAddBracketsButton setState:[defaults boolForKey:EditorCanAddBracketsKey]];
    [_lineNumberButton setState:[defaults boolForKey:LineNumberEnabledKey]];
    [_tagMenuButton setState:[defaults boolForKey:TagMenuInMenuBarKey]];
    [_showInvisibleCharactersButton setState:[defaults boolForKey:ShowInvisibleCharactersEnabledKey]];
    [_midEastButton setState:[defaults boolForKey:RightJustifyKey]];
    [_blockCursorButton setState:[defaults boolForKey:BlockCursorKey]];
    NSColor *BlockCursorColor = [NSColor colorWithCalibratedRed:[defaults floatForKey:BlockCursorRKey]
                                                          green:[defaults floatForKey:BlockCursorGKey]
                                                           blue:[defaults floatForKey:BlockCursorBKey]
                                                          alpha:1.0];
    [BlockCursorColorWell setColor:BlockCursorColor];
    [_alwaysHighlightButton setState:![defaults boolForKey:AlwaysHighlightEnabledKey]];
    [_showIndicatorForMoveButton setState:[defaults boolForKey:ShowIndicatorForMoveEnabledKey]];
    [_highlightContentButton setState:[defaults boolForKey:HighlightContentEnabledKey]];
    [_beepButton setState:[defaults boolForKey:BeepEnabledKey]];
    [_flashBackgroundButton setState:[defaults boolForKey:FlashBackgroundEnabledKey]];
    [_checkBraceButton setState:[defaults boolForKey:CheckBraceEnabledKey]];
    [_checkBracketButton setState:[defaults boolForKey:CheckBracketEnabledKey]];
    [_checkSquareBracketButton setState:[defaults boolForKey:CheckSquareBracketEnabledKey]];
    [_checkParenButton setState:[defaults boolForKey:CheckParenEnabledKey]];
    [_showTabCharacterButton setState:[defaults boolForKey:showTabCharacterKey]];
    [_showSpaceCharacterButton setState:[defaults boolForKey:showSpaceCharacterKey]];
    [_showFullwidthSpaceCharacterButton setState:[defaults boolForKey:showFullwidthSpaceCharacterKey]];
    [_showNewLineCharacterButton setState:[defaults boolForKey:showNewLineCharacterKey]];
    [self updateInvisibleCharacterControls:defaults];
    [_makeatletterButton setState:[defaults boolForKey:MakeatletterEnabledKey]];
    [_expl3SyntaxColorButton setState:[defaults boolForKey:expl3SyntaxColoringKey]];
    [XMLchapter setState:[defaults boolForKey:XMLChapterTagKey]];
    [XMLsection setState:[defaults boolForKey:XMLSectionTagKey]];
    [XMLsubsection setState:[defaults boolForKey:XMLSubsectionTagKey]];
    [XMLsubsubsection setState:[defaults boolForKey:XMLSubsubsectionTagKey]];
    [XMLintroduction setState:[defaults boolForKey:XMLIntroductionTagKey]];
    [XMLconclusion setState:[defaults boolForKey:XMLConclusionTagKey]];
    [XMLexercises setState:[defaults boolForKey:XMLExercisesTagKey]];
    [XMLproject setState:[defaults boolForKey:XMLProjectTagKey]];
    [XMLfigure setState:[defaults boolForKey:XMLFigureTagKey]];
    [XMLtable setState:[defaults boolForKey:XMLTableTagKey]];
    [XMLmark setState:[defaults boolForKey:XMLMarkTagKey]];
    if ([[defaults stringForKey:BlockWidthKey] isEqualToString:@"0"])
        [_blockWidthMatrix selectCellWithTag:0];
    else
        [_blockWidthMatrix selectCellWithTag:1];
    if ([[defaults stringForKey:BlockSideKey] isEqualToString:@"0"])
        [_blockSideMatrix selectCellWithTag:0];
    else if ([[defaults stringForKey:BlockSideKey] isEqualToString:@"1"])
        [_blockSideMatrix selectCellWithTag:1];
    else
        [_blockSideMatrix selectCellWithTag:2];
    if ([defaults integerForKey:LineBreakModeKey] == 0)
        [_wrapMatrix selectCellWithTag:0];
    else if ([defaults integerForKey:LineBreakModeKey] == 1)
        [_wrapMatrix selectCellWithTag:1];
    else
        [_wrapMatrix selectCellWithTag:2];
    if ([defaults integerForKey:FindMethodKey] == 0)
        [_findMatrix selectCellWithTag:0];
    else if ([defaults integerForKey:FindMethodKey] == 1)
        [_findMatrix selectCellWithTag:1];
    else
        [_findMatrix selectCellWithTag:2];
    if ([defaults integerForKey:LineNumberSizeKey] == 0)
        [_lineSizeMatrix selectCellWithTag:0];
    else if ([defaults integerForKey:LineNumberSizeKey] == 1)
        [_lineSizeMatrix selectCellWithTag:1];
    else
        [_lineSizeMatrix selectCellWithTag:2];
    tabSize = [defaults integerForKey:tabsKey];
    myNumber = [NSNumber numberWithInteger:tabSize];
    [tabIndentField setStringValue:[myNumber stringValue]];
    [firstParagraphIndentField setIntegerValue:[defaults integerForKey:SourceFirstLineHeadIndentKey]];
    [remainingParagraphIndentField setIntegerValue:[defaults integerForKey:SourceHeadIndentKey]];
    if ([defaults integerForKey:SourceInterlineSpaceKey] == 0)
        [interlineSpacingField setIntegerValue:1];
    else
        [interlineSpacingField setIntegerValue:[defaults integerForKey:SourceInterlineSpaceKey]];
    [self setSettingsControl:BlockCursorColorWell enabled:YES];
    [self setSettingsControl:_blockSideMatrix enabled:YES];
    [self setSettingsControl:_blockWidthMatrix enabled:YES];
}

- (void)refreshSpellingSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [_spellCheckButton setState:[defaults boolForKey:SpellCheckEnabledKey]];
    [_autoSpellCorrectButton setState:[defaults boolForKey:AutomaticSpellingCorrectionEnabledKey]];
    [_spellCheckCommands setState:[defaults boolForKey:TurnOffCommandSpellCheckKey]];
    [_spellCheckParameters setState:[defaults boolForKey:TurnOffParameterSpellCheckKey]];
    [_spellCheckComments setState:[defaults boolForKey:TurnOffCommentSpellCheckKey]];
    [self updateSpellingControlsFromDefaults:defaults];
    [dictionaryPopup removeAllItems];
    [dictionaryPopup addItemWithTitle:NSLocalizedString(@"Automatic Language", @"")];
    NSArray *theLanguages = [[NSSpellChecker sharedSpellChecker] availableLanguages];
    NSInteger numberOfItems = [theLanguages count];
    NSInteger i = 0;
    while (i < numberOfItems)
    {
        [dictionaryPopup addItemWithTitle:[theLanguages objectAtIndex:i]];
        i = i + 1;
    }
    BOOL useAutomatic = [defaults boolForKey:spellingAutomaticDefaultKey];
    NSString *myLanguage = [defaults objectForKey:spellingLanguageDefaultKey];
    if (useAutomatic)
        [dictionaryPopup selectItemAtIndex:0];
    else
    {
        i = 0;
        while (i < numberOfItems)
        {
            if ([myLanguage isEqualToString:[dictionaryPopup itemTitleAtIndex:(i + 1)]])
                [dictionaryPopup selectItemAtIndex:(i + 1)];
            i = i + 1;
        }
    }
}

- (void)refreshAppearanceSettingsFromDefaults:(NSUserDefaults *)defaults
{
    // Theme values are refreshed by PrepareColorPane/FillInColorWells.
    // Category navigation preserves the currently edited theme.
    (void)defaults;
}

- (void)refreshPreviewSettingsFromDefaults:(NSUserDefaults *)defaults
{
    double magnification;
    NSInteger mag;
    NSNumber *myNumber;
#ifdef MITSU_PDF
    NSInteger myTag, itemIndex;
#endif
    [_autoPDFButton setState:[defaults boolForKey:PdfRefreshKey]];
    [_antialiasButton setState:[defaults boolForKey:AntiAliasKey]];
    [_scrollButton setState:[defaults boolForKey:NoScrollEnabledKey]];
    magnification = [defaults floatForKey:PdfMagnificationKey];
    mag = round(magnification * 100.0);
    myNumber = [NSNumber numberWithInteger:mag];
    [_magTextField setStringValue:[myNumber stringValue]];
#ifdef MITSU_PDF
    myTag = [defaults integerForKey:PdfFirstPageStyleKey];
    if (!myTag)
        myTag = PDF_FIRST_RIGHT;
    [_firstPageMatrix selectCellWithTag:myTag];
    [_displayAsBookButton setState:[defaults boolForKey:DisplayAsBookKey] ? NSControlStateValueOn : NSControlStateValueOff];
    myTag = [defaults integerForKey:PdfPageStyleKey];
    if (!myTag)
        myTag = PDF_SINGLE_PAGE_STYLE;
    itemIndex = [_pageStylePopup indexOfItemWithTag:myTag];
    if (itemIndex == -1)
        itemIndex = 2;
    [_pageStylePopup selectItemAtIndex:itemIndex];
    myTag = [defaults integerForKey:PdfKitFitSizeKey];
    if (!myTag)
        myTag = NEW_PDF_FIT_TO_WINDOW;
    itemIndex = [_resizeOptionPopup indexOfItemWithTag:myTag];
    if (itemIndex == -1)
        itemIndex = 2;
    [_resizeOptionPopup selectItemAtIndex:itemIndex];
    myTag = [defaults integerForKey:PdfCopyTypeKey];
    if (!myTag)
        myTag = IMAGE_TYPE_JPEG_MEDIUM;
    itemIndex = [_imageCopyTypePopup indexOfItemWithTag:myTag];
    if (itemIndex == -1)
        itemIndex = 1;
    [_imageCopyTypePopup selectItemAtIndex:itemIndex];
    myTag = [defaults integerForKey:PdfKitMouseModeKey];
    if (!myTag)
        myTag = NEW_MOUSE_MODE_SELECT_TEXT;
    itemIndex = [_mouseModePopup indexOfItemWithTag:myTag];
    if (itemIndex == -1)
        itemIndex = 1;
    [_mouseModePopup selectItemAtIndex:itemIndex];
    [_colorMapButton setState:[defaults boolForKey:PdfColorMapKey] ? NSOnState : NSOffState];
    myTag = [defaults integerForKey:PdfColorParam1Key];
    itemIndex = [_colorParam1Popup indexOfItemWithTag:myTag];
    if (itemIndex == -1)
        itemIndex = 2;
    [_colorParam1Popup selectItemAtIndex:itemIndex];
#endif
    [_HtmlHomeField setStringValue:[defaults stringForKey:HtmlHomeKey] ?: @""];
    [self setSettingsControl:_colorParam1Popup enabled:[defaults boolForKey:PdfColorMapKey]];
}

- (void)refreshTypesettingSettingsFromDefaults:(NSUserDefaults *)defaults
{
#ifdef MITSU_PDF
    NSInteger myTag, myInteger;
#endif
    [_escapeWarningButton setState:[defaults boolForKey:WarnForShellEscapeKey]];
    [_ptexUtfOutputButton setState:[defaults boolForKey:ptexUtfOutputEnabledKey]];
    NSString *kpsetool = [defaults objectForKey:KpsetoolKey];
    if (!kpsetool || [kpsetool isEqualToString:@""])
    {
        kpsetool = @"kpsetool -w -n latex tex";
    }
    [_kpsetoolField setStringValue:kpsetool];
    NSString *bibTeXengine = [defaults objectForKey:BibTeXengineKey];
    if (!bibTeXengine || [bibTeXengine isEqualToString:@""])
    {
        bibTeXengine = @"bibtex";
    }
    [_bibTeXengineField setStringValue:bibTeXengine];
    [_savePSButton setState:[defaults boolForKey:SavePSEnabledKey]];
#ifdef MITSU_PDF
    myTag = [defaults integerForKey:DistillerCommandKey];
    [_distillerMatrix selectCellWithTag:myTag];
    myInteger = [defaults integerForKey:BringFrontOnTypesetKey];
    myTag = myInteger;
    [_afterTypesettingMatrix selectCellWithTag:myTag];
#endif
    [_texCommandTextField setStringValue:[defaults stringForKey:TexCommandKey] ?: @""];
    [_latexCommandTextField setStringValue:[defaults stringForKey:LatexCommandKey] ?: @""];
    [_texGSCommandTextField setStringValue:[defaults stringForKey:TexGSCommandKey] ?: @""];
    [_latexGSCommandTextField setStringValue:[defaults stringForKey:LatexGSCommandKey] ?: @""];
    [_tetexBinPathField setStringValue:[defaults stringForKey:TetexBinPath] ?: @""];
    [_altPathField setStringValue:[defaults stringForKey:AltPathKey] ?: @""];
    [_gsBinPathField setStringValue:[defaults stringForKey:GSBinPath] ?: @""];
    [_texScriptCommandTextField setStringValue:[defaults stringForKey:TexScriptCommandKey] ?: @""];
    [_latexScriptCommandTextField setStringValue:[defaults stringForKey:LatexScriptCommandKey] ?: @""];
    [_alternateEngineTextField setStringValue:[defaults stringForKey:AlternateEngineKey] ?: @""];
    [_defaultCommandMatrix selectCellWithTag:[defaults integerForKey:DefaultCommandKey]];
    [_engineTextField setStringValue:[defaults stringForKey:DefaultEngineKey] ?: @""];
    if ([defaults integerForKey:DefaultCommandKey] == 2)
    {
        [_engineTextField setEnabled:YES];
        [_engineTextField setEditable:YES];
        [_engineTextField setSelectable:YES];
    }
    else
        [_engineTextField setEnabled:NO];
    if ([defaults integerForKey:DefaultCommandKey] == 2)
        [_engineTextField setEditable:YES];
    [_defaultScriptMatrix selectCellWithTag:[defaults integerForKey:DefaultScriptKey]];
    if (![_syncMatrix selectCellWithTag:[defaults integerForKey:SyncMethodKey]])
    {
        [_syncMatrix setAllowsEmptySelection:YES];
        [_syncMatrix deselectAllCells];
        [_syncMatrix setAllowsEmptySelection:NO];
    }
    [_useTransparencyButton setState:[defaults boolForKey:UseTransparencyKey]];
    [_syncTabButton setState:[defaults boolForKey:SyncUseTabsKey]];
}

- (void)refreshConsoleSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [self updateConsoleFontTextField];
    [_consoleMatrix selectCellWithTag:[defaults integerForKey:ConsoleBehaviorKey]];
    [_macroButton setState:[defaults boolForKey:SameFontForMacroKey]];
    if ([defaults boolForKey:ConsoleWidthResizeKey] == YES)
        [_consoleResizeMatrix selectCellWithTag:0];
    else
        [_consoleResizeMatrix selectCellWithTag:1];
}

- (void)refreshKeyboardSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [_autoCompleteButton setState:[defaults boolForKey:AutoCompleteEnabledKey]];
    [_bibDeskCompleteButton setState:[defaults boolForKey:BibDeskCompletionKey]];
    if ([[defaults stringForKey:CommandCompletionCharKey] isEqualToString:@"ESCAPE"])
        [_commandCompletionMatrix selectCellWithTag:0];
    else
        [_commandCompletionMatrix selectCellWithTag:1];
}

- (void)refreshUpdatesSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [_sparkleAutomaticButton setState:[defaults boolForKey:SparkleAutomaticUpdateKey]];
    [_sparkleIntervalMatrix setEnabled:[defaults boolForKey:SparkleAutomaticUpdateKey]];
    [_sparkleIntervalMatrix selectCellWithTag:[defaults integerForKey:SparkleIntervalKey]];
#ifdef USESPARKLE
    if (defaults == SUD && [TSSparkleController sharedUpdater] != nil)
    {
        SPUUpdater *updater = [TSSparkleController sharedUpdater];
        [_sparkleAutomaticButton setState:updater.automaticallyChecksForUpdates];
        [_sparkleIntervalMatrix setEnabled:updater.automaticallyChecksForUpdates];
        NSTimeInterval interval = updater.updateCheckInterval;
        [_sparkleIntervalMatrix selectCellWithTag:(interval < 604800 ? 1 : (interval < 2629800 ? 2 : 3))];
    }
#endif
}

- (void)updateSettingsCategory:(TSSettingsCategoryID)identifier fromDefaults:(NSUserDefaults *)defaults
{
    if ([identifier isEqual:TSSettingsCategoryGeneral])
    {
        [self refreshGeneralSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryDocuments])
    {
        [self refreshDocumentsSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryEditor])
    {
        [self refreshEditorSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategorySpelling])
    {
        [self refreshSpellingSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryAppearance])
    {
        [self refreshAppearanceSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryPreview])
    {
        [self refreshPreviewSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryTypesetting])
    {
        [self refreshTypesettingSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryConsole])
    {
        [self refreshConsoleSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryKeyboard])
    {
        [self refreshKeyboardSettingsFromDefaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryUpdates])
    {
        [self refreshUpdatesSettingsFromDefaults:defaults];
        return;
    }
}

- (void)updateControlsFromUserDefaults:(NSUserDefaults *)defaults
{
    // Opening the window and applying a profile refresh all categories once.
    [self updateSettingsCategory:TSSettingsCategoryGeneral fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryDocuments fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryEditor fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategorySpelling fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryAppearance fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryPreview fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryTypesetting fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryConsole fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryKeyboard fromDefaults:defaults];
    [self updateSettingsCategory:TSSettingsCategoryUpdates fromDefaults:defaults];
}
