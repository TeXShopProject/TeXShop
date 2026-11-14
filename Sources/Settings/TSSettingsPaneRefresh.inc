// SPDX-License-Identifier: GPL-2.0-or-later
// Category-owned display refresh; original nib outlets remain compatibility adapters.
- (void)refreshGeneralSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [_sourceWindowPosMatrix selectCellWithTag:[defaults integerForKey:DocumentWindowPosModeKey]];
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
    [_pdfWindowPosMatrix selectCellWithTag:[defaults integerForKey:PdfWindowPosModeKey]];
    [_htmlWindowPosMatrix selectCellWithTag:[defaults integerForKey:HtmlWindowPosModeKey]];
    [self setSettingsControl:useLeftSourceButton enabled:YES];
    [self setSettingsControl:useRightSourceButton enabled:YES];
}

- (void)refreshDocumentsSettingsFromDefaults:(NSUserDefaults *)defaults
{
    [_convertUTFButton setState:[defaults boolForKey:AutomaticUTF8MACtoUTF8ConversionKey]];
    [_autoSaveEnabledButton setState:[defaults boolForKey:AutoSaveEnabledKey]];
    [_keepBackupButton setState:[defaults boolForKey:KeepBackupKey]];
    [_saveEncodingMenuButton setState:[defaults boolForKey:EncodingMenuInSaveDialogKey]];
    [_defaultEncodeMatrix removeAllItems];
    [[TSEncodingSupport sharedInstance] addEncodingsToMenu:[_defaultEncodeMatrix menu] withTarget:0 action:0];
    [_defaultEncodeMatrix selectItemWithTag:[[TSEncodingSupport sharedInstance] defaultEncoding]];
    [_saveRelatedButton setState:[defaults boolForKey:SaveRelatedKey]];
}

- (void)refreshEditorSettingsFromDefaults:(NSUserDefaults *)defaults
{
    NSData *fontData, *attributesData;
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
    NSInteger findMethod = [defaults integerForKey:FindMethodKey];
    [_findMatrix selectCellWithTag:(findMethod >= 0 && findMethod <= 3 ? findMethod : 0)];
    if ([defaults integerForKey:LineNumberSizeKey] == 0)
        [_lineSizeMatrix selectCellWithTag:0];
    else if ([defaults integerForKey:LineNumberSizeKey] == 1)
        [_lineSizeMatrix selectCellWithTag:1];
    else
        [_lineSizeMatrix selectCellWithTag:2];
    [tabIndentField setIntegerValue:TSStoredIntegerInRange(defaults, tabsKey, TSTabWidthRange)];
    [firstParagraphIndentField setIntegerValue:TSStoredIntegerInRange(defaults, SourceFirstLineHeadIndentKey, TSParagraphIndentRange)];
    [remainingParagraphIndentField setIntegerValue:TSStoredIntegerInRange(defaults, SourceHeadIndentKey, TSParagraphIndentRange)];
    [interlineSpacingField setIntegerValue:TSStoredIntegerInRange(defaults, SourceInterlineSpaceKey, TSInterlineSpaceRange)];
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
    // Each choice keeps the checker's identifier; its title is the language's name.
    NSArray<NSString *> *theLanguages = [[NSSpellChecker sharedSpellChecker] availableLanguages] ?: @[];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSString *language in theLanguages) [titles addObject:TSSpellingLanguageDisplayName(language)];
    NSCountedSet<NSString *> *titleCounts = [[NSCountedSet alloc] initWithArray:titles];
    for (NSUInteger i = 0; i < theLanguages.count; i++) {
        NSString *title = titles[i];
        if ([titleCounts countForObject:title] > 1) title = [NSString stringWithFormat:@"%@ (%@)", title, theLanguages[i]];
        NSMenuItem *item = [dictionaryPopup.menu addItemWithTitle:title action:NULL keyEquivalent:@""];
        item.representedObject = theLanguages[i];
        item.toolTip = theLanguages[i];
    }
    NSString *myLanguage = nil;
    if (TSSpellingDefaultIsAutomatic(defaults, nil, &myLanguage)) {
        [dictionaryPopup selectItemAtIndex:0];
        return;
    }
    NSString *match = TSSpellingLanguageMatching(myLanguage, theLanguages);
    if (match == nil && TSSpellingLanguageNormalized(myLanguage).length > 0) {
        // A dictionary that is no longer installed stays visible as the current choice.
        NSMenuItem *item = [dictionaryPopup.menu addItemWithTitle:TSSpellingLanguageDisplayName(myLanguage) action:NULL keyEquivalent:@""];
        item.representedObject = myLanguage;
        item.toolTip = myLanguage;
        match = myLanguage;
    }
    NSInteger index = match ? [dictionaryPopup indexOfItemWithRepresentedObject:match] : -1;
    [dictionaryPopup selectItemAtIndex:index >= 0 ? index : 0];
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
    [_linkPopupsButton setState:[defaults boolForKey:LinkPopupsKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [_scrollPageTurnButton setState:[defaults boolForKey:NoScrollPageTurnKey] ? NSControlStateValueOn : NSControlStateValueOff];
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
        kpsetool = @"kpsewhich -progname=latex -format=tex";
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
    [self refreshDefaultEngineFromDefaults:defaults];
    [_defaultScriptMatrix selectCellWithTag:[defaults integerForKey:DefaultScriptKey]];
    if (![_syncMatrix selectCellWithTag:[defaults integerForKey:SyncMethodKey]])
    {
        [_syncMatrix setAllowsEmptySelection:YES];
        [_syncMatrix deselectAllCells];
        [_syncMatrix setAllowsEmptySelection:NO];
    }
    [_useTransparencyButton setState:[defaults boolForKey:UseTransparencyKey]];
    [_syncTabButton setState:[defaults boolForKey:SyncUseTabsKey]];
    [self refreshEngineProfileFromDefaults:defaults];
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

    [_sparkleIntervalMatrix selectCellWithTag:[defaults integerForKey:SparkleIntervalKey]];
    self.sparklePrereleaseButton.state = [defaults boolForKey:SparklePrereleaseUpdatesKey] ? NSControlStateValueOn : NSControlStateValueOff;
    if (defaults == SUD) [self refreshSparkleLastCheck];
#ifdef USESPARKLE
    if (defaults == SUD && [TSSparkleController sharedUpdater] != nil)
    {
        SPUUpdater *updater = [TSSparkleController sharedUpdater];
        [_sparkleAutomaticButton setState:updater.automaticallyChecksForUpdates];

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
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryDocuments])
    {
        [self refreshDocumentsSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryEditor])
    {
        [self refreshEditorSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategorySpelling])
    {
        [self refreshSpellingSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryAppearance])
    {
        [self refreshAppearanceSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryPreview])
    {
        [self refreshPreviewSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryTypesetting])
    {
        [self refreshTypesettingSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryConsole])
    {
        [self refreshConsoleSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryKeyboard])
    {
        [self refreshKeyboardSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
        return;
    }
    if ([identifier isEqual:TSSettingsCategoryUpdates])
    {
        [self refreshUpdatesSettingsFromDefaults:defaults];
        [self updateSettingsDependenciesForCategory:identifier defaults:defaults];
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
