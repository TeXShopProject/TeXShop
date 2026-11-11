// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferences+Panes.h"
#import "TSPrefSourceController.h"
#import "TSPrefEditorController.h"
#import "TSPrefPreviewController.h"
#import "TSPrefConsoleController.h"
#import "TSPrefTypesettingController.h"
#import "TSPrefEnginesController.h"
#import "TSPrefMiscOneController.h"
#import "TSPrefMiscTwoController.h"
#import "TSPrefThemesController.h"
#import "TSPrefFooterController.h"
#import "TSPrefThemeNameController.h"
#import "TSSettingsCategory.h"
#import "TSPrefPaneLayout.h"
#import "TSAppDelegate.h"
#include "TSSettingsPaneClassification.inc"
@implementation TSPreferences (Panes)
- (NSArray<TSPrefPaneController *> *)makeSettingsPanes
{
    TSPrefSourceController *source = [TSPrefSourceController new];
    source.preferences = self;
    (void)source.view;
    source.categoryIdentifier = TSSettingsCategorySource;
    TSPrefEditorController *editor = [TSPrefEditorController new];
    editor.preferences = self;
    (void)editor.view;
    editor.categoryIdentifier = TSSettingsCategoryEditor;
    TSPrefPreviewController *preview = [TSPrefPreviewController new];
    preview.preferences = self;
    (void)preview.view;
    preview.categoryIdentifier = TSSettingsCategoryPreview;
    TSPrefConsoleController *console = [TSPrefConsoleController new];
    console.preferences = self;
    (void)console.view;
    console.categoryIdentifier = TSSettingsCategoryConsole;
    TSPrefTypesettingController *typesetting = [TSPrefTypesettingController new];
    typesetting.preferences = self;
    (void)typesetting.view;
    typesetting.categoryIdentifier = TSSettingsCategoryTypesetting;
    TSPrefEnginesController *engines = [TSPrefEnginesController new];
    engines.preferences = self;
    (void)engines.view;
    engines.categoryIdentifier = TSSettingsCategoryEngines;
    TSPrefMiscOneController *miscOne = [TSPrefMiscOneController new];
    miscOne.preferences = self;
    (void)miscOne.view;
    miscOne.categoryIdentifier = TSSettingsCategoryMiscOne;
    TSPrefMiscTwoController *miscTwo = [TSPrefMiscTwoController new];
    miscTwo.preferences = self;
    (void)miscTwo.view;
    miscTwo.categoryIdentifier = TSSettingsCategoryMiscTwo;
    TSPrefThemesController *themes = [TSPrefThemesController new];
    themes.preferences = self;
    (void)themes.view;
    themes.categoryIdentifier = TSSettingsCategoryThemes;
    TSPrefFooterController *footer = [TSPrefFooterController new];
    footer.preferences = self;
    (void)footer.view;
    TSPrefThemeNameController *themeName = [TSPrefThemeNameController new];
    themeName.preferences = self;
    (void)themeName.view;

    _texAwareSpellCheckButton = source.texAwareSpellCheckButton;
    _editSpellingExclusionsButton = source.editSpellingExclusionsButton;
    _checkBraceButton = source.checkBraceButton;
    _checkBracketButton = source.checkBracketButton;
    _checkParenButton = source.checkParenButton;
    _checkSquareBracketButton = source.checkSquareBracketButton;
    _commandCompletionMatrix = source.commandCompletionMatrix;
    _defaultEncodeMatrix = source.defaultEncodeMatrix;
    _docWindowPosButton = source.docWindowPosButton;
    _documentFontTextField = source.documentFontTextField;
    _externalEditorButton = source.externalEditorButton;
    _findMatrix = source.findMatrix;
    _lineSizeMatrix = source.lineSizeMatrix;
    _openAsTabsMatrix = source.openAsTabsMatrix;
    _openEmptyButton = source.openEmptyButton;
    _sourceWindowPosMatrix = source.sourceWindowPosMatrix;
    _spellCheckCommands = source.spellCheckCommands;
    _spellCheckComments = source.spellCheckComments;
    _spellCheckParameters = source.spellCheckParameters;
    dictionaryPopup = source.dictionaryPopup;
    _FullwidthSpaceCharacterKindPopup = editor.FullwidthSpaceCharacterKindPopup;
    _NewLineCharacterKindPopup = editor.NewLineCharacterKindPopup;
    _SpaceCharacterKindPopup = editor.SpaceCharacterKindPopup;
    _TabCharacterKindPopup = editor.TabCharacterKindPopup;
    _alwaysHighlightButton = editor.alwaysHighlightButton;
    _autoCompleteButton = editor.autoCompleteButton;
    _autoSpellCorrectButton = editor.autoSpellCorrectButton;
    _beepButton = editor.beepButton;
    _bibDeskCompleteButton = editor.bibDeskCompleteButton;
    _editorAddBracketsButton = editor.editorAddBracketsButton;
    _flashBackgroundButton = editor.flashBackgroundButton;
    _highlightContentButton = editor.highlightContentButton;
    _lineNumberButton = editor.lineNumberButton;
    _midEastButton = editor.midEastButton;
    _parensMatchButton = editor.parensMatchButton;
    _selectActivateButton = editor.selectActivateButton;
    _showFullwidthSpaceCharacterButton = editor.showFullwidthSpaceCharacterButton;
    _showIndicatorForMoveButton = editor.showIndicatorForMoveButton;
    _showInvisibleCharactersButton = editor.showInvisibleCharactersButton;
    _showNewLineCharacterButton = editor.showNewLineCharacterButton;
    _showSpaceCharacterButton = editor.showSpaceCharacterButton;
    _showTabCharacterButton = editor.showTabCharacterButton;
    _spellCheckButton = editor.spellCheckButton;
    _syntaxColorButton = editor.syntaxColorButton;
    _makeatletterButton = editor.makeatletterButton;
    _expl3SyntaxColorButton = editor.expl3SyntaxColorButton;
    _syntaxColorLineButton = editor.syntaxColorLineButton;
    _tabIndentButton = editor.tabIndentButton;
    _tagMenuButton = editor.tagMenuButton;
    _wrapMatrix = editor.wrapMatrix;
    firstParagraphIndentField = editor.firstParagraphIndentField;
    interlineSpacingField = editor.interlineSpacingField;
    remainingParagraphIndentField = editor.remainingParagraphIndentField;
    tabIndentField = editor.tabIndentField;
    _HtmlHomeField = preview.HtmlHomeField;
    _autoPDFButton = preview.autoPDFButton;
    _displayAsBookButton = preview.displayAsBookButton;
    _linkPopupsButton = preview.linkPopupsButton;
    _scrollPageTurnButton = preview.scrollPageTurnButton;
    _firstPageMatrix = preview.firstPageMatrix;
    _htmlWindowPosButton = preview.htmlWindowPosButton;
    _htmlWindowPosMatrix = preview.htmlWindowPosMatrix;
    _magTextField = preview.magTextField;
    _mouseModePopup = preview.mouseModePopup;
    _pageStylePopup = preview.pageStylePopup;
    _pdfWindowPosButton = preview.pdfWindowPosButton;
    _pdfWindowPosMatrix = preview.pdfWindowPosMatrix;
    _resizeOptionPopup = preview.resizeOptionPopup;
    useLeftSourceButton = preview.useLeftSourceButton;
    useOneWindowButton = preview.useOneWindowButton;
    useRightSourceButton = preview.useRightSourceButton;
    useTwoWindowsButton = preview.useTwoWindowsButton;
    _consoleFontTextField = console.consoleFontTextField;
    _consoleMatrix = console.consoleMatrix;
    _consoleResizeMatrix = console.consoleResizeMatrix;
    _consoleWindowPosButton = console.consoleWindowPosButton;
    _consoleWindowPosMatrix = console.consoleWindowPosMatrix;
    _macroButton = console.macroButton;
    _afterTypesettingMatrix = typesetting.afterTypesettingMatrix;
    _defaultCommandMatrix = typesetting.defaultCommandMatrix;
    _defaultScriptMatrix = typesetting.defaultScriptMatrix;
    _engineTextField = typesetting.engineTextField;
    _saveRelatedButton = typesetting.saveRelatedButton;
    _syncMatrix = typesetting.syncMatrix;
    _syncTabButton = typesetting.syncTabButton;
    _useTransparencyButton = typesetting.useTransparencyButton;
    _altPathField = engines.altPathField;
    _bibTeXengineField = engines.bibTeXengineField;
    _escapeWarningButton = engines.escapeWarningButton;
    _gsBinPathField = engines.gsBinPathField;
    _kpsetoolField = engines.kpsetoolField;
    _latexCommandTextField = engines.latexCommandTextField;
    _latexGSCommandTextField = engines.latexGSCommandTextField;
    _savePSButton = engines.savePSButton;
    _tetexBinPathField = engines.tetexBinPathField;
    _texCommandTextField = engines.texCommandTextField;
    _texGSCommandTextField = engines.texGSCommandTextField;
    BlockCursorColorWell = miscOne.BlockCursorColorWell;
    BlockCursorColorWell.supportsAlpha = NO; // the block cursor color is stored without opacity
    _blockCursorButton = miscOne.blockCursorButton;
    _blockSideMatrix = miscOne.blockSideMatrix;
    _blockWidthMatrix = miscOne.blockWidthMatrix;
    _colorMapButton = miscOne.colorMapButton;
    _colorParam1Popup = miscOne.colorParam1Popup;
    _imageCopyTypePopup = miscOne.imageCopyTypePopup;
    _autoSaveEnabledButton = miscOne.autoSaveEnabledButton;
    _keepBackupButton = miscOne.keepBackupButton;
    _saveEncodingMenuButton = miscOne.saveEncodingMenuButton;
    XMLchapter = miscTwo.XMLchapter;
    XMLconclusion = miscTwo.XMLconclusion;
    XMLexercises = miscTwo.XMLexercises;
    XMLfigure = miscTwo.XMLfigure;
    XMLintroduction = miscTwo.XMLintroduction;
    XMLmark = miscTwo.XMLmark;
    XMLproject = miscTwo.XMLproject;
    XMLsection = miscTwo.XMLsection;
    XMLsubsection = miscTwo.XMLsubsection;
    XMLsubsubsection = miscTwo.XMLsubsubsection;
    XMLtable = miscTwo.XMLtable;
    _alternateEngineTextField = miscTwo.alternateEngineTextField;
    _convertUTFButton = miscTwo.convertUTFButton;
    _latexScriptCommandTextField = miscTwo.latexScriptCommandTextField;
    _miniaturizeRootFileButton = miscTwo.miniaturizeRootFileButton;
    _openRootFileButton = miscTwo.openRootFileButton;
    _ptexUtfOutputButton = miscTwo.ptexUtfOutputButton;
    _sparkleAutomaticButton = miscTwo.sparkleAutomaticButton;
    _sparkleIntervalMatrix = miscTwo.sparkleIntervalMatrix;
    _texScriptCommandTextField = miscTwo.texScriptCommandTextField;
    ConsoleAlphaColorWell = themes.ConsoleAlphaColorWell;
    ConsoleBackgroundColorWell = themes.ConsoleBackgroundColorWell;
    ConsoleTextColorWell = themes.ConsoleTextColorWell;
    DarkStyle = themes.DarkStyle;
    EditingStyle = themes.EditingStyle;
    EditorFlashColorWell = themes.EditorFlashColorWell;
    EditorHighlightBracesColorWell = themes.EditorHighlightBracesColorWell;
    EditorHighlightContentColorWell = themes.EditorHighlightContentColorWell;
    EditorInvisibleCharColorWell = themes.EditorInvisibleCharColorWell;
    EditorHighlightZenkakuSymbolColorWell = themes.EditorHighlightZenkakuSymbolColorWell;
    EditorHighlightZenkakuSymbolBackgroundColorWell = themes.EditorHighlightZenkakuSymbolBackgroundColorWell;
    EditorReverseSyncColorWell = themes.EditorReverseSyncColorWell;
    EntryColorWell = themes.EntryColorWell;
    FootnoteColorWell = themes.FootnoteColorWell;
    ImageBackgroundColorWell = themes.ImageBackgroundColorWell;
    ImageForegroundColorWell = themes.ImageForegroundColorWell;
    LiteStyle = themes.LiteStyle;
    LogBackgroundColorWell = themes.LogBackgroundColorWell;
    LogTextColorWell = themes.LogTextColorWell;
    PreviewAlphaColorWell = themes.PreviewAlphaColorWell;
    PreviewBackgroundColorWell = themes.PreviewBackgroundColorWell;
    PreviewDirectSyncColorWell = themes.PreviewDirectSyncColorWell;
    SourceAlphaColorWell = themes.SourceAlphaColorWell;
    SourceBackgroundColorWell = themes.SourceBackgroundColorWell;
    SourceInsertionPointColorWell = themes.SourceInsertionPointColorWell;
    SourceTextColorWell = themes.SourceTextColorWell;
    SyntaxCommandColorWell = themes.SyntaxCommandColorWell;
    SyntaxCommentColorWell = themes.SyntaxCommentColorWell;
    SyntaxIndexColorWell = themes.SyntaxIndexColorWell;
    SyntaxMarkerColorWell = themes.SyntaxMarkerColorWell;
    XMLCommentColorWell = themes.XMLCommentColorWell;
    XMLParameterColorWell = themes.XMLParameterColorWell;
    XMLSpecialColorWell = themes.XMLSpecialColorWell;
    XMLTagColorWell = themes.XMLTagColorWell;
    XMLValueColorWell = themes.XMLValueColorWell;
    explFunctionColorWell = themes.explFunctionColorWell;
    explIntenseFunctionColorWell = themes.explIntenseFunctionColorWell;
    explIntenseVariableColorWell = themes.explIntenseVariableColorWell;
    explVariableColorWell = themes.explVariableColorWell;
    explmsgColorWell = themes.explmsgColorWell;
    explmykeyArgumentColorWell = themes.explmykeyArgumentColorWell;
    explmykeyColorWell = themes.explmykeyColorWell;
    markerCurlyColorWell = themes.markerCurlyColorWell;
    markerParenColorWell = themes.markerParenColorWell;
    markerSquareColorWell = themes.markerSquareColorWell;
    stylePanel = themeName.stylePanel;
    styleTitle = themeName.styleTitle;
    return @[source, editor, preview, console, typesetting, engines, miscOne, miscTwo, themes, footer, themeName];
}
- (NSDictionary<TSSettingsCategoryID, NSViewController *> *)classifySettingsPanes:(NSArray<TSPrefPaneController *> *)panes
{
    return [TSSettingsPaneComposer compose:panes preferences:self];
}
@end
