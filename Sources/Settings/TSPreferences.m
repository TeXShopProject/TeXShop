/*
 * SUUpdate = KOCHSU
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2007 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * $Id: TSPreferences.m 254 2007-06-03 21:09:25Z fingolfin $
 *
 * Created by dirk on Thu Dec 07 2000.
 *
 */
#import "TSShortcutPaneController.h"
#import "TSPreferences+Panes.h"
#import "TSPrefFooterController.h"


#import "UseMitsu.h"
#import "UseSparkle.h"

#import "TSPreferences+LiveSettings.h"
#import "TSSettingsWindowController.h"
#import "TSEnginePathDiscovery.h"
#import "TSPreferenceProfile.h"
#import "TSPreferenceInput.h"
#import "TSSourceFormatRanges.h"
#import "TSColorSupport.h"
#import "TSInvisibleCharacters.h"
#import "TSDockIconController.h"
#import "TSKeyboardShortcuts.h"
#import "TSSpellSupport.h"
#import "TSWindowManager.h"
#import "TSEncodingSupport.h"
#import "globals.h"
#import "TSAutoCompletionListEditor.h"
#import "HelpDocuments.h"
#import "TSPreviewWindow.h"
#import "TSSettingsChangeNote.h"
#import "TSPreferenceEffects.h"
#import "TSAppDelegate.h" // mitsu 1.29 (O)
#import "TSDocument.h"
#import "TSConsoleWindow.h"
#ifdef USESPARKLE
    #import "TSSparkleController.h"
#endif

//#import "MyPDFView.h" // mitsu 1.29 (O)

// SUD reads the domain named by the bundle identifier, so whole-domain writes
// must target that same domain. A fixed @"TeXShop" overwrote the official
// build's settings whenever a build with another identifier ran for the first time.
static NSString *TSPreferencesDomainName(void)
{
	return [[NSBundle mainBundle] bundleIdentifier] ?: @"TeXShop";
}


typedef NS_CLOSED_ENUM(NSUInteger, TSSettingsFontDestination) {
    TSSettingsFontNone, TSSettingsFontDocument, TSSettingsFontConsole
};

@interface TSPreferences () <NSWindowDelegate, NSTextFieldDelegate, TSSettingsWindowDelegate>
@property (strong) TSSettingsWindowController *settingsController;
@property (copy) NSArray<TSPrefPaneController *> *preferencePanes;
@property TSSettingsFontDestination fontEditingContext;
@property (strong) NSMapTable<NSControl *, TSPreferenceInput *> *inputRules;
@property (strong) TSPreferenceEditing *inputEditing;
@property BOOL inputErrorPresented;
@property BOOL ownsFontPanel;
@property BOOL endingPreferences;
@property NSUInteger enginePathSearchGeneration;
@property BOOL initialEnginePathSearchPending;
@property (weak) NSButton *enginePathSearchButton;
- (void)searchEnginePathsForInitialSetup:(BOOL)initial sender:(NSButton *)sender;
- (void)refreshRuntimePreferences;
@end

@implementation TSPreferences
@synthesize legacySpellCheckButton = _legacySpellCheckButton, keyBindingEditor = _keyBindingEditor, settingsHelpDocuments = _settingsHelpDocuments;
/*"
Format of the original prefs file:

_{#position #value}
_{0 version number}
_{1 textView's font}
_{2 pdfView's slider value}
_{3-6 textWindow's frame}
_{7-10 pdfWindow's frame}
_{11 TeX command}
_{12 LaTeX command}
_{13 display method (Apple or GS)}
_{14 GS color}
_{15 preferred TeX command}
"*/

static id _sharedInstance = nil;

/*" This class is implemented as singleton, i.e. there is only one single instance in the runtime. This is the designated accessor method to get the shared instance of the Preferences class.
"*/
+ (id)sharedInstance
{
	if (_sharedInstance == nil)
	{
		_sharedInstance = [[TSPreferences alloc] init];
	}
	return _sharedInstance;
}

- (id)init
{
	if (_sharedInstance != nil) {
//		[super dealloc]; // huh? Weird code; Feb 24, 2009, RMK
		return _sharedInstance;
	}
	_sharedInstance = self;
	// setup the default font here so it's defined when we run for the first time.
	self.documentFont = [NSFont userFontOfSize:12.0];
    self.fontAttributes = nil;
	// self.consoleFont = [NSFont userFixedPitchedFontOfSize:10.0];

	// register for changes in the user defaults
	
	// I now believe this is not needed; Feb 24, 2009 RMK
	// [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];

	return self;
}



//==============================================================================
// target/action methods
//==============================================================================
/*" Connected to the "Preferences..." menu item in Application's main menu.

Loads the .nib file if necessary, fills all the controls with the values from the user defaults and makes the window visible.
"*/
- (IBAction)showPreferences:(id)sender
{
    if ((_prefsWindow.visible || _prefsWindow.miniaturized)) { [_prefsWindow makeKeyAndOrderFront:sender]; return; }
    if (!self.initialEnginePathSearchPending) [self cancelEnginePathDiscovery];
    if (![self prepareSettingsWindow]) return;
    self.endingPreferences = NO;
    self.inputErrorPresented = NO;
    _prefsWindow.delegate = self;
    [self configurePreferenceInputs];
    [[TSDockIconController sharedController] installInPreferencesPane:[self.settingsController viewForCategoryIdentifier:TSSettingsCategoryGeneral]];
    [[TSDockIconController sharedController] restoreSavedIcon];
    [self updateControlsFromUserDefaults:SUD];
    [self PrepareColorPane:SUD];
    [self.settingsController beginSession];
    [_prefsWindow makeKeyAndOrderFront:self];
}

- (void)showKeyboardSettings:(id)sender
{
    [self showPreferences:sender];
    if (self.settingsController == nil) { return; }
    [self.settingsController selectCategoryIdentifier:TSSettingsCategoryKeyboard];
}

- (BOOL)prepareSettingsWindow
{
    if (self.settingsController != nil) return YES;
    self.preferencePanes = [self makeSettingsPanes];
    TSSettingsWindowController *controller = [[TSSettingsWindowController alloc] initWithDefaults:SUD];
    NSWindow *newWindow = controller.window;
    if (newWindow == nil) return NO;
    controller.settingsDelegate = self;
    NSDictionary<TSSettingsCategoryID, NSViewController *> *panes = [self classifySettingsPanes:self.preferencePanes];
    self.settingsChangeNotes = [[TSSettingsChangeNotes alloc] initWithDefaults:SUD launchValues:TSSettingsLaunchValues() bundle:NSBundle.mainBundle];
    self.settingsChangeNotes.hasSourceWindow = ^BOOL { return [[TSWindowManager sharedInstance] activeTextWindow] != nil; };
    self.settingsChangeNotes.hasPDFWindow = ^BOOL {
        for (id document in NSDocumentController.sharedDocumentController.documents)
            if ([document isKindOfClass:TSDocument.class]) {
                NSWindow *preview = ((TSDocument *)document).pdfKitWindow;
                NSWindow *combined = [document fullSplitWindow];
                if (preview.visible || preview.miniaturized || combined.visible || combined.miniaturized) return YES;
            }
        return NO;
    };
    [self.settingsChangeNotes attachToPanes:panes];
    controller.changeNotes = self.settingsChangeNotes;
    NSView *keyboardOptions = panes[TSSettingsCategoryKeyboard].view;
    controller.commandNamesProvider = ^NSArray<NSString *> * {
        return [[TSKeyboardShortcuts sharedController].store settingsSearchCommandNames] ?: @[];
    };
    controller.keyboardPaneProvider = ^NSViewController<TSSettingsKeyboardPane> * {
        TSShortcutPaneController *keyboard = [[TSShortcutPaneController alloc] initWithShortcuts:[TSKeyboardShortcuts sharedController]];
        keyboard.settingsHeader = keyboardOptions;
        return keyboard;
    };
    NSView *footer = nil;
    for (TSPrefPaneController *pane in self.preferencePanes) {
        if ([pane isKindOfClass:TSPrefFooterController.class]) { footer = pane.view; }
    }
    if (footer == nil) { return NO; }
    [controller hostPaneControllers:panes footer:footer];
    _prefsWindow = newWindow;
    self.settingsController = controller;
    return YES;
}
- (BOOL)settingsMayChangeCategory
{
    if (![self finishPreferenceEditing:YES]) return NO;
    [self releasePreferencePanels];
    return YES;
}
- (void)settingsWillDisplayCategory:(TSSettingsCategoryID)identifier
{
    [self updateSettingsCategory:identifier fromDefaults:SUD];
}
- (void)settingsChangeFont:(NSFontManager *)sender
{
    [self changeFont:sender];
}

//==============================================================================
// Entire panel
//==============================================================================
/*" This method is connected to the 'Set Defaults' menu


"*/

//-----------------------------------



- (IBAction)setDefaults:(NSMenuItem *)sender
{
    if (![self finishPreferenceEditing:YES]) return;
    NSString *name = TSPreferenceProfileNameForTag((TSPreferenceProfileTag)sender.tag);
    if (name == nil) return;
    NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"plist" subdirectory:@"Defaults"];
    if (url == nil) return;
    NSDictionary<NSString *, id> *profile = [NSDictionary dictionaryWithContentsOfURL:url];
    NSFont *font = [NSFont userFontOfSize:12.0];
    if (profile == nil || font == nil) return;
    NSURL *factoryURL = [NSBundle.mainBundle URLForResource:@"FactoryDefaults" withExtension:@"plist" subdirectory:@"Defaults"];
    NSDictionary<NSString *, id> *factory = factoryURL == nil ? nil : [NSDictionary dictionaryWithContentsOfURL:factoryURL];
    if (factory == nil) return;
    TSPreferenceProfile *proposal = [[TSPreferenceProfile alloc] initWithProfile:profile
        documentFont:[NSArchiver archivedDataWithRootObject:font] registeredDefaults:factory];
    if (proposal == nil) { [self showPreferenceError:NSLocalizedString(@"The selected profile is invalid.", @"")]; return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Apply Settings Profile?", @"");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"Resets engine, editing, display, known hidden settings, and the Dock icon. Theme selections may change. TeX engine path: %@", @""), proposal.enginePath];
    [alert addButtonWithTitle:NSLocalizedString(@"Apply Profile", @"")].keyEquivalent = @"";
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")].keyEquivalent = @"\e";
    __weak TSPreferences *weakSelf = self;
    [alert beginSheetModalForWindow:_prefsWindow completionHandler:^(NSModalResponse response) {
        TSPreferences *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.endingPreferences || response != NSAlertFirstButtonReturn) return;
        [strongSelf cancelEnginePathDiscovery];
        [strongSelf releasePreferencePanels];
        [strongSelf applyPreferenceProfile:proposal font:font];
    }];
}


// Compare effective values, then reuse the notifications of individual actions.
- (void)applyPreferenceProfile:(TSPreferenceProfile *)proposal font:(NSFont *)font
{
    NSMutableDictionary<NSString *, id> *before = [NSMutableDictionary dictionary];
    for (NSString *key in TSKnownPreferenceKeys()) before[key] = [SUD objectForKey:key] ?: NSNull.null;
    [proposal applyToDefaults:SUD];
    [self.settingsChangeNotes valuesReplaced];
    NSMutableSet<NSString *> *changed = [NSMutableSet set];
    for (NSString *key in TSKnownPreferenceKeys())
        if (![before[key] isEqual:[SUD objectForKey:key] ?: NSNull.null]) [changed addObject:key];
    self.documentFont = font;
    self.fontAttributes = nil;
    [self refreshRuntimePreferences];
    [self updateControlsFromUserDefaults:SUD];
    [self PrepareColorPane:SUD];
    [self applyEffectsForPreferenceKeys:changed];
}

- (void)applyEffectsForPreferenceKeys:(NSSet<NSString *> *)changed
{
    TSPreferencePreparation preparations = TSPreferencePreparationsForKeys(changed);
    if (preparations & TSPreferencePreparePDFCopy) [(TSAppDelegate *)NSApp.delegate syncImageCopyTypeMenu];
    if (preparations & TSPreferencePrepareDock) [[TSDockIconController sharedController] restoreSavedIcon];
    if (preparations & TSPreferencePrepareEncoding) [[TSEncodingSupport sharedInstance] setupForEncoding];
    if (preparations & TSPreferencePrepareSpelling) [TSSpellSupport preferencesDidChange];
    if (preparations & TSPreferencePrepareTheme) [[TSColorSupport sharedInstance] initializeColors];
    TSPostPreferenceNotifications(changed, self);
}

// Refresh the process-wide copies after a group of settings has changed.
// Individual controls update their own copy at the point of persistence.
- (void)refreshRuntimePreferences
{
    editorCanAddBrackets = [SUD boolForKey:EditorCanAddBracketsKey];
    PreviewBackgroundColor = [NSColor colorWithCalibratedRed:[SUD floatForKey:PdfPageBack_RKey]
        green:[SUD floatForKey:PdfPageBack_GKey] blue:[SUD floatForKey:PdfPageBack_BKey] alpha:1];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
    [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"")] setHidden:![SUD boolForKey:TagMenuInMenuBarKey]];
}

//==============================================================================
// Document pane
//==============================================================================
/*" This method is connected to the 'Set...' button on the 'Document' pane.

Clicking this button will bring up the font panel.
"*/

- (IBAction)changeDocumentFont:sender
{
    // self.documentFont = [fontManager convertFont:self.documentFont];
    if (![self finishPreferenceEditing:YES]) return;
    self.ownsFontPanel = YES;
    self.fontEditingContext = TSSettingsFontDocument;
    [_prefsWindow makeFirstResponder:_prefsWindow];
    [[NSFontManager sharedFontManager] setSelectedFont:self.documentFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (IBAction)changeConsoleResize:sender
{
	if ([[_consoleResizeMatrix selectedCell] tag] == 0) 
		[SUD setBool:YES forKey:ConsoleWidthResizeKey];	
	else 
		[SUD setBool:NO forKey:ConsoleWidthResizeKey];
}



- (IBAction)changeConsoleFont:sender
{
	self.consoleFont = [NSFont fontWithName: [SUD stringForKey:ConsoleFontNameKey] size:[SUD floatForKey:ConsoleFontSizeKey]];
	
	// become first responder so we will see the envents that NSFontManager sends
	// up the responder chain
	if (![self finishPreferenceEditing:YES]) return;
    self.ownsFontPanel = YES;
    self.fontEditingContext = TSSettingsFontConsole;
	[_prefsWindow makeFirstResponder:_prefsWindow];
	[[NSFontManager sharedFontManager] setSelectedFont:self.consoleFont isMultiple:NO];
	[[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}



/*" This method is sent down the responder chain by the font manager when changing fonts in the font panel. Since this class is delegate of the Window, we will receive this method and we can reflect the changes in the textField accordingly.
"*/
- (void)changeFont:(id)fontManager
{
    if (!self.ownsFontPanel || self.endingPreferences ||
        !(_prefsWindow.isKeyWindow || _prefsWindow.isMainWindow)) return;
    
    NSData    *fontData;
    TSSettingsFontDestination destination = self.fontEditingContext;

	if (destination == TSSettingsFontDocument)
		{

		self.documentFont = [fontManager convertFont:self.documentFont];


		[self updateDocumentFontTextField];

		// update the userDefaults
		fontData = [NSArchiver archivedDataWithRootObject:self.documentFont];
		[SUD setObject:fontData forKey:DocumentFontKey];
		[SUD setBool:YES forKey:SaveDocumentFontKey];

		// post a notification so all open documents can change their font
		TSPostPreferenceNotifications([NSSet setWithObject:DocumentFontKey], self);

		}
		
	else if (destination == TSSettingsFontConsole)
		{
		self.consoleFont = [fontManager convertFont:self.consoleFont];
		[SUD setObject: [self.consoleFont fontName] forKey:ConsoleFontNameKey];
		[SUD setFloat: [self.consoleFont pointSize] forKey: ConsoleFontSizeKey];
		[self updateConsoleFontTextField];
		TSPostPreferenceNotifications([NSSet setWithObject:ConsoleFontNameKey], self);
		}
}

/*" This method is connected to the "Source Window Position" Matrix.

This method will be called when the matrix changes. Target 0 means 'all windows start at a fixed position', target 1 means 'remember window position'.
"*/
- (IBAction)sourceWindowPosChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:DocumentWindowPosModeKey];
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

/*" This method is connected to the 'use current pos as default' button on the 'Document' pane.
"*/
- (IBAction)currentDocumentWindowPosDefault:sender
{
	NSWindow	*activeWindow;

	activeWindow = [[TSWindowManager sharedInstance] activeTextWindow];

	if (activeWindow != nil) {
		[SUD setObject:[activeWindow stringWithSavedFrame] forKey:DocumentWindowFixedPosKey];

		// just in case: the radio button must be checked as well.
		/* koch: the code below is harmless but probably unnecessary since the button can only
			be pressed if the radio button is in the fixed position mode */
		[SUD setInteger:DocumentWindowPosFixed forKey:DocumentWindowPosModeKey];
		[_sourceWindowPosMatrix selectCellWithTag:DocumentWindowPosFixed];
	}
}

// added by Terada( - (IBAction)highlightChanged: )
- (IBAction)highlightChanged:(id)sender
{
	[SUD setBool:![_alwaysHighlightButton state] forKey:AlwaysHighlightEnabledKey];
	
	[SUD setBool:[_showIndicatorForMoveButton state] forKey:ShowIndicatorForMoveEnabledKey];
	
	[SUD setBool:[_highlightContentButton state] forKey:HighlightContentEnabledKey];
	
	[SUD setBool:[_beepButton state] forKey:BeepEnabledKey];
	
	[SUD setBool:[_flashBackgroundButton state] forKey:FlashBackgroundEnabledKey];
	
	[SUD setBool:[_checkBraceButton state] forKey:CheckBraceEnabledKey];
	
	[SUD setBool:[_checkBracketButton state] forKey:CheckBracketEnabledKey];
	
	[SUD setBool:[_checkSquareBracketButton state] forKey:CheckSquareBracketEnabledKey];
	
	[SUD setBool:[_checkParenButton state] forKey:CheckParenEnabledKey];
	
	TSPostPreferenceNotifications([NSSet setWithArray:@[AlwaysHighlightEnabledKey, ShowIndicatorForMoveEnabledKey, HighlightContentEnabledKey, BeepEnabledKey, FlashBackgroundEnabledKey, CheckBraceEnabledKey, CheckBracketEnabledKey, CheckSquareBracketEnabledKey, CheckParenEnabledKey]], self);
}

- (void)updateInvisibleCharacterControls:(NSUserDefaults *)defaults
{
    NSArray *popups = @[_SpaceCharacterKindPopup, _FullwidthSpaceCharacterKindPopup,
                        _NewLineCharacterKindPopup, _TabCharacterKindPopup];
    NSArray *buttons = @[_showSpaceCharacterButton, _showFullwidthSpaceCharacterButton,
                         _showNewLineCharacterButton, _showTabCharacterButton];
    NSArray *keys = @[SpaceCharacterKindKey, FullwidthSpaceCharacterKindKey,
                      NewLineCharacterKindKey, TabCharacterKindKey];
    for (NSUInteger n = 0; n < popups.count; n++) {
        NSPopUpButton *popup = popups[n];
        NSButton *button = buttons[n];
        NSArray<NSString *> *markers = TSInvisibleMarkers(keys[n]);
        if (![popup.itemTitles isEqual:markers]) {
            [popup removeAllItems];
            [popup addItemsWithTitles:markers];
        }
        for (NSInteger i = 0; i < popup.numberOfItems; i++) [popup itemAtIndex:i].tag = i;
        popup.font = [NSFont systemFontOfSize:15];
        popup.menu.font = popup.font;
        popup.accessibilityLabel = button.title;
        [popup selectItemAtIndex:TSInvisibleStoredIndex(defaults, keys[n])];

    }
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryEditor defaults:defaults];
}

// added by Terada( - (IBAction)invisibleCharacterChanged: )
- (IBAction)invisibleCharacterChanged:(id)sender
{
	[SUD setBool:[_showTabCharacterButton state] forKey:showTabCharacterKey];
	
	[SUD setBool:[_showSpaceCharacterButton state] forKey:showSpaceCharacterKey];
	
	[SUD setBool:[_showFullwidthSpaceCharacterButton state] forKey:showFullwidthSpaceCharacterKey];
	
	[SUD setBool:[_showNewLineCharacterButton state] forKey:showNewLineCharacterKey];
	
	TSSetInvisibleIndex(SUD, SpaceCharacterKindKey, [_SpaceCharacterKindPopup selectedItem].tag);
	
	TSSetInvisibleIndex(SUD, FullwidthSpaceCharacterKindKey, [_FullwidthSpaceCharacterKindPopup selectedItem].tag);
	
	TSSetInvisibleIndex(SUD, NewLineCharacterKindKey, [_NewLineCharacterKindPopup selectedItem].tag);
	
	TSSetInvisibleIndex(SUD, TabCharacterKindKey, [_TabCharacterKindPopup selectedItem].tag);
	
    [self updateInvisibleCharacterControls:SUD];
	TSPostPreferenceNotifications([NSSet setWithArray:@[showTabCharacterKey, showSpaceCharacterKey, showFullwidthSpaceCharacterKey, showNewLineCharacterKey, SpaceCharacterKindKey, FullwidthSpaceCharacterKindKey, NewLineCharacterKindKey, TabCharacterKindKey]], self);
	
}

// added by Terada( - (IBAction)makeatletterChanged: )
- (IBAction)makeatletterChanged:(id)sender
{
	[SUD setBool:[_makeatletterButton state] forKey:MakeatletterEnabledKey];
	
	TSPostPreferenceNotifications([NSSet setWithArray:@[MakeatletterEnabledKey]], self);
}

// Each document reads this when it opens; the Source menu still turns expl3 coloring on and off for one document.
- (IBAction)expl3SyntaxColorPressed:sender
{
	[SUD setBool:(_expl3SyntaxColorButton.state == NSControlStateValueOn) forKey:expl3SyntaxColoringKey];    TSPostPreferenceNotifications([NSSet setWithArray:@[expl3SyntaxColoringKey]], self);
}

// Persist immediately; NSDocument autosave and server watching change at next launch.
- (IBAction)autoSaveEnabledPressed:sender
{
    id previousNoteValue = @([SUD boolForKey:AutoSaveEnabledKey]);
	[SUD setBool:(_autoSaveEnabledButton.state == NSControlStateValueOn) forKey:AutoSaveEnabledKey];
	// A backup file is kept only when Versions is off, which follows autosave.
	[self updateSettingsDependenciesForCategory:TSSettingsCategoryDocuments defaults:SUD];
    [self.settingsChangeNotes recordUserChangeForKey:AutoSaveEnabledKey previousValue:previousNoteValue];
}

- (IBAction)keepBackupPressed:sender
{
	[SUD setBool:(_keepBackupButton.state == NSControlStateValueOn) forKey:KeepBackupKey];
}

- (IBAction)saveEncodingMenuPressed:sender
{
	[SUD setBool:(_saveEncodingMenuButton.state == NSControlStateValueOn) forKey:EncodingMenuInSaveDialogKey];
}

// added by Terada( - (IBAction)kpsetoolChanged: )
- (IBAction)kpsetoolChanged:(id)sender
{
    [self commitPreferenceField:_kpsetoolField showError:YES reflect:YES];
}

// added by Terada( - (IBAction)bibTeXengineChanged: )
- (IBAction)bibTeXengineChanged:(id)sender
{
    [self commitPreferenceField:_bibTeXengineField showError:YES reflect:YES];
}


/*" Set Command Completion Key"*/
- (IBAction)commandCompletionChanged:sender
{
	
	if ([[sender selectedCell] tag] == 0)
		[SUD setObject:@"ESCAPE" forKey:CommandCompletionCharKey];
	else
		[SUD setObject:@"TAB" forKey:CommandCompletionCharKey];
	TSPostPreferenceNotifications([NSSet setWithArray:@[CommandCompletionCharKey]], self);
	
}



/*" Set Find Panel"*/
- (IBAction)findPanelChanged:sender
{
    id previousNoteValue = @([SUD integerForKey:FindMethodKey]);

	if ([[sender selectedCell] tag] == 0)
		[SUD setInteger:0 forKey:FindMethodKey];
	else if ([[sender selectedCell] tag] == 1)
		[SUD setInteger:1 forKey:FindMethodKey];
    else
        [SUD setInteger:2 forKey:FindMethodKey];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:FindMethodKey]];
    [self.settingsChangeNotes recordUserChangeForKey:FindMethodKey previousValue:previousNoteValue];
}

/*" Set Line Number Size"*/
- (IBAction)lineSizeChanged:sender
{

    if ([[sender selectedCell] tag] == 0)
        [SUD setInteger:0 forKey:LineNumberSizeKey];
    else if ([[sender selectedCell] tag] == 1)
        [SUD setInteger:1 forKey:LineNumberSizeKey];
    else
        [SUD setInteger:0 forKey:LineNumberSizeKey];
}


/*" Set Wrap Panel"*/
- (IBAction)wrapPanelChanged:sender
{
    
    if ([[sender selectedCell] tag] == 0)
        [SUD setInteger:0 forKey:LineBreakModeKey];
    else if ([[sender selectedCell] tag] == 1)
        [SUD setInteger:1 forKey:LineBreakModeKey];
    else
        [SUD setInteger:2 forKey:LineBreakModeKey];
}



/*" Make Empty Document on Startup "*/
- (IBAction)emptyButtonPressed:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:MakeEmptyDocumentKey];
}

/*" Configure for External Editor "*/
- (IBAction)externalEditorButtonPressed:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:UseExternalEditorKey];
	 // post a notification so the system will learn about this change
	TSPostPreferenceNotifications([NSSet setWithObject:UseExternalEditorKey], self);
}


/*" Change Encoding "*/
- (IBAction)encodingChanged:sender
{
	NSString	*oldValue, *value;
	NSStringEncoding	theCode;

	oldValue = [SUD stringForKey:EncodingKey];

	theCode = [[sender selectedCell] tag];
	value = [[TSEncodingSupport sharedInstance] keyForStringEncoding: theCode];
	[SUD setObject:value forKey:EncodingKey];

	// added by mitsu --(G) TSEncodingSupport
	[self applyEffectsForPreferenceKeys:[NSSet setWithObject:EncodingKey]];
    [self.settingsChangeNotes recordUserChangeForKey:EncodingKey previousValue:oldValue ?: @""];
// end addition

}

/*" Change Window Opening Behavior "*/
- (IBAction)openAsTabsChanged:sender
{
    NSInteger value;

    value = [[sender selectedCell] tag];
    [SUD setInteger:value forKey:OpenAsTabsKey];
}


- (IBAction)tabIndentPressed:(id)sender
{
    [self commitPreferenceField:tabIndentField showError:YES reflect:YES];
}

- (IBAction)firstParagraphIndentPressed:(id)sender
{
    [self commitPreferenceField:firstParagraphIndentField showError:YES reflect:YES];
}

- (IBAction)remainingParagraphIndentPressed:(id)sender
{
    [self commitPreferenceField:remainingParagraphIndentField showError:YES reflect:YES];
}

- (IBAction)interlineSpacingPressed:(id)sender
{
    [self commitPreferenceField:interlineSpacingField showError:YES reflect:YES];
}



- (IBAction)useTabPressed:sender
{
    
    [SUD setBool:[(NSButton*)sender state] forKey:TabIndentKey];
}


/*" This method is connected to the 'syntax coloring' checkbox.
"*/
- (IBAction)syntaxColorPressed:sender
{

    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:SyntaxColoringEnabledKey];
    TSPostPreferenceNotifications([NSSet setWithArray:@[SyntaxColoringEnabledKey]], self);
}



/*" This method is connected to the 'syntax line coloring' checkbox.
"*/
- (IBAction)syntaxColorLinePressed:sender
{

     
    [SUD setBool: [(NSCell *)sender state]  forKey:SyntaxColorEntryLineKey];
    TSPostPreferenceNotifications([NSSet setWithArray:@[SyntaxColorEntryLineKey]], self);
}

/*" This method is connected to the 'block cursor' checkbox.
"*/
- (IBAction)blockCursorPressed:sender
{

     
    [SUD setBool: [(NSCell *)sender state]  forKey:BlockCursorKey];
    [self updateSettingsDependenciesFromDefaults:SUD];
}

/*" This method is connected to the 'use font for log and macro editor' checkbox.
"*/
- (IBAction)MacroPressed:sender
{

     
    [SUD setBool: [(NSCell *)sender state]  forKey:SameFontForMacroKey];
}


- (IBAction)blockWidthPressed:sender
{
    NSInteger   selectedValue;
    

    if ([[sender selectedCell] tag] == 0)
        selectedValue = 0;
    else
        selectedValue = 1;
    
    [SUD setInteger: selectedValue forKey:BlockWidthKey];
}


- (IBAction)blockSidePressed:sender
{
    NSInteger   selectedValue;
    

    /*
    if ([[sender selectedCell] tag] == 0)
        selectedValue = 0;
    else
        selectedValue = 1;
    */
    selectedValue = [[sender selectedCell] tag];
    
    [SUD setInteger: selectedValue forKey:BlockSideKey];
}


/*" This method is connected to the block cursor color well.
 "*/
- (IBAction)BlockCursorColorChanged:sender
{
    NSColor *newColor = [((NSColorWell *)sender).color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    if (newColor == nil) return;
    
    
    [SUD setFloat: [newColor redComponent] forKey:BlockCursorRKey];
    [SUD setFloat: [newColor greenComponent] forKey:BlockCursorGKey];
    [SUD setFloat: [newColor blueComponent] forKey: BlockCursorBKey];
}



/*" This method is connected to the "Source Window Position" Matrix.
 
 This method will be called when the matrix changes. Target 0 means 'all windows start at a fixed position', target 1 means 'remember window position'.
 "*/
- (IBAction)consoleWindowPosChanged:sender
{
    
    [SUD setInteger:[[sender selectedCell] tag] forKey:ConsoleWindowPosModeKey];
    [_consoleWindowPosMatrix selectCellWithTag:[[sender selectedCell] tag]];
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

/*" This method is connected to the 'use current pos as default' button on the 'Document' pane.
 "*/
- (IBAction)consoleWindowPosDefault:sender
{
    NSMutableArray  *visibleWindows;
    NSEnumerator    *windowsEnumerator;
    id              anObject;
    NSWindow        *activeConsole;
    
    
    visibleWindows = [NSMutableArray arrayWithCapacity: 37];
    
    
    NSArray *myWindows = [[NSApplication sharedApplication] windows];
    windowsEnumerator = [myWindows objectEnumerator];
    while (anObject = [windowsEnumerator nextObject])
        if ([(NSWindow *)anObject isVisible])
            [visibleWindows addObject: anObject];
    
    // NSLog(@"There are %lu windows", (unsigned long)[visibleWindows count]);

    windowsEnumerator = [visibleWindows objectEnumerator];
    while ((activeConsole = [windowsEnumerator nextObject]) &&
           ( ! [activeConsole isKindOfClass: [TSConsoleWindow class]]))
    {
        ;
    }
    
    if (! activeConsole)
    {
//      NSLog(@"no console");
        return;
    }
    
//    if (  [activeConsole isKindOfClass: [TSConsoleWindow class]])
//        NSLog(@"this is a console");
    
//    NSLog(@"found one");
    
    if (activeConsole != nil) {
        [SUD setObject:[activeConsole stringWithSavedFrame] forKey:ConsoleWindowFixedPosKey];
        
        // just in case: the radio button must be checked as well.
        /* koch: the code below is harmless but probably unnecessary since the button can only
         be pressed if the radio button is in the fixed position mode */
        [SUD setInteger:ConsoleWindowPosFixed forKey:ConsoleWindowPosModeKey];
        [_consoleWindowPosMatrix selectCellWithTag:ConsoleWindowPosFixed];
    }
}


- (IBAction)XMLChapterButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLChapterTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSectionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSubsectionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSubsectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSubsubsectionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSubsubsectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLIntroductionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLIntroductionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLConclusionButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLConclusionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLExercisesButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLExercisesTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLProjectButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLProjectTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLFigureButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLFigureTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLTableButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLTableTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLMarkButtonChanged:(id)sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:XMLMarkTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}










/*" This method is connected to the 'select on activate' checkbox.
"*/
- (IBAction)selectActivatePressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AcceptFirstMouseKey];
}


/*" This method is connected to the 'parens matching' checkbox.
"*/
- (IBAction)parensMatchPressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:ParensMatchingEnabledKey];
}

/*" This method is connected to the 'spell checking' checkbox.
"*/
- (IBAction)spellCheckPressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:SpellCheckEnabledKey];
}

- (IBAction)editorAddBracketsPressed:(id)sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:EditorCanAddBracketsKey];
    editorCanAddBrackets = [SUD boolForKey:EditorCanAddBracketsKey];
}

- (IBAction)spellCorrectPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AutomaticSpellingCorrectionEnabledKey];
}


/*" This method is connected to the 'line number' checkbox.
"*/
- (IBAction)lineNumberButtonPressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:LineNumberEnabledKey];
}

/*" This method is connected to the 'tags menu' checkbox.
 "*/
- (IBAction)tagMenuButtonPressed:sender
{
    
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:TagMenuInMenuBarKey];
     [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] setHidden:( ![SUD boolForKey:TagMenuInMenuBarKey])];
}


// added by Terada (-(IBAction)showInvisibleCharacterButtonPressed:)
- (IBAction)showInvisibleCharacterButtonPressed:sender
{
	
	[SUD setBool:[(NSCell *)sender state] forKey:ShowInvisibleCharactersEnabledKey];    TSPostPreferenceNotifications([NSSet setWithArray:@[ShowInvisibleCharactersEnabledKey]], self);
}

/*" This method is connected to the 'Arabic, Persian, Hebrew' checkbox.
 "*/
- (IBAction)midEastButtonPressed:sender
{
	
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:RightJustifyKey];
}





/*" This method is connected to the 'shell escape warning' checkbox.
"*/
- (IBAction)escapeWarningChanged:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:WarnForShellEscapeKey];
}


/*" This method is connected to the 'auto complete' checkbox.
"*/
- (IBAction)autoCompletePressed:sender
{

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AutoCompleteEnabledKey];
	TSPostPreferenceNotifications([NSSet setWithArray:@[AutoCompleteEnabledKey]], self);

}

/*" This method is connected to the 'BibDesk Complete' checkbox.
"*/
- (IBAction)bibDeskCompletePressed:sender
{
	
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:BibDeskCompletionKey];
	TSPostPreferenceNotifications([NSSet setWithArray:@[BibDeskCompletionKey]], self);

}





//==============================================================================
// Preview pane
//==============================================================================
/*" This method is connected to the "PDF Window Position" Matrix.

A tag of 0 means don't save the window position, a tag of 1 to save the setting. This should only flag the request to save the position, the actual saving of position and size can be left to [NSWindow setAutoSaveFrameName].
"*/
- (IBAction)pdfWindowPosChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfWindowPosModeKey];

	/* koch: button enabled only if appropriate */
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

//==============================================================================
/*" This method is connected to the "HTML Window Position" Matrix.

A tag of 0 means don't save the window position, a tag of 1 to save the setting. This should only flag the request to save the position, the actual saving of position and size can be left to [NSWindow setAutoSaveFrameName].
"*/
- (IBAction)htmlWindowPosChanged:sender
{

    [SUD setInteger:[[sender selectedCell] tag] forKey:HtmlWindowPosModeKey];

    /* koch: button enabled only if appropriate */
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryGeneral defaults:SUD];
}

/*" This method is connected to the 'use current pos as default' button.
"*/
- (IBAction)currentPdfWindowPosDefault:sender
{
	NSWindow	*activeWindow;

	activeWindow = [[TSWindowManager sharedInstance] activePDFWindow];

	if (activeWindow != nil) {
		[SUD setObject:[activeWindow stringWithSavedFrame] forKey:PdfWindowFixedPosKey];

		// just in case: the radio button must be checked as well.
		[SUD setInteger:DocumentWindowPosFixed forKey:PdfWindowPosModeKey];
		[_pdfWindowPosMatrix selectCellWithTag:PdfWindowPosFixed];
	}
}

/*" This method is connected to the 'use current pos as default' button.
"*/
- (IBAction)currentHtmlWindowPosDefault:sender
{
    NSWindow    *activeWindow;

    activeWindow = [[TSWindowManager sharedInstance] activeHTMLWindow];

    if (activeWindow != nil) {
        [SUD setObject:[activeWindow stringWithSavedFrame] forKey:HtmlWindowFixedPosKey];

        // just in case: the radio button must be checked as well.
       //  [SUD setInteger:HtmlWindowPosFixed forKey:HtmlWindowPosModeKey];
       //  [_sourceWindowPosMatrix selectCellWithTag:HtmlWindowPosFixed];
    }
}


/*" This method is connected to the magnification text field on the Preview pane'.
"*/
- (IBAction)magChanged:(id)sender
{
    [self commitPreferenceField:_magTextField showError:YES reflect:YES];
}



- (IBAction)autoPDFChanged:sender
{
	[SUD setBool:[(NSCell *)sender state] forKey:PdfRefreshKey];
}

// The state of Link Popups in the Preview menu when a Preview window opens.
- (IBAction)linkPopupsChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:LinkPopupsKey];
}

// Whether scrolling stops at the edge of the page in single and double page display.
- (IBAction)scrollPageTurnChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:NoScrollPageTurnKey];
}

- (IBAction)sourceAndPreviewInSameWindowChanged:sender
{
    NSInteger myTag = [sender tag];
    BOOL result;
    if (myTag == 0)
        result = NO;
    else
        result = YES;
	[SUD setBool:result forKey:SourceAndPreviewInSameWindowKey];
    [self updateSettingsDependenciesFromDefaults:SUD];
}

- (IBAction)sourceOnLeftChanged:sender
{
    NSInteger myTag = [sender tag];
    BOOL result;
    if (myTag == 0)
        result = NO;
    else
        result = YES;
    [SUD setBool:result forKey:SwitchSidesKey];
}



#ifdef MITSU_PDF

// mitsu 1.29 (O)
/*" This method is connected to page style popup button. "*/
- (IBAction)pageStyleChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfPageStyleKey];
}

/*" This method is connect to the 'first double page' radio buttons.
"*/
- (IBAction)displayAsBookChanged:(NSButton *)sender
{
    [SUD setBool:sender.state == NSControlStateValueOn forKey:DisplayAsBookKey];
}

- (IBAction)firstDoublePageChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfFirstPageStyleKey];
}


- (IBAction)defaultEngineCall:sender //Koch; change one of four engine Unix calls
{
	NSString *defaultValue;
	
	NSInteger			which = [sender tag];
	
	switch (which) {
		case 0: defaultValue = @"pdftex --file-line-error --synctex=1";
				[_texCommandTextField setStringValue: defaultValue];
				[self texProgramChanged: nil];
				break;
			
		case 1: defaultValue = @"pdflatex --file-line-error --synctex=1";
				[_latexCommandTextField setStringValue: defaultValue];
				[self latexProgramChanged: nil];
				break;

		case 2: defaultValue = @"simpdftex etex --maxpfb --extratexopts \"-file-line-error -synctex=1\"";
				[_texGSCommandTextField setStringValue: defaultValue];
				[self texGSProgramChanged: nil];
				break;

		case 3: defaultValue = @"simpdftex latex --maxpfb --extratexopts \"-file-line-error -synctex=1\"";
				[_latexGSCommandTextField setStringValue: defaultValue];
				[self latexGSProgramChanged: nil];
				break;
	}
}


/*" This method is connected to resize option popup button. "*/
- (IBAction)resizeOptionChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfKitFitSizeKey];
}


/*" This method is connected to image copy type popup button. "*/
- (IBAction)imageCopyTypeChanged:sender
{
	// mitsu 1.29b
	// uncheck menu item Preview=>Copy Format
	NSMenu *previewMenu = [[[NSApp mainMenu] itemWithTitle:
						NSLocalizedString(@"Preview", @"Preview")] submenu];

	NSMenu *formatMenu = [[previewMenu itemWithTitle:
						NSLocalizedString(@"Copy Format", @"Copy Format")] submenu];
	id item = [formatMenu itemWithTag: [[sender selectedCell] tag]];
	if (item)
		[(TSAppDelegate *)[NSApp delegate] changeImageCopyType: item];
	// end mitsu 1.29b
}

// mitsu 1.29b
- (NSPopUpButton *)imageCopyTypePopup
{
	return _imageCopyTypePopup;
}
// end mitsu 1.29b


/*" This method is connected to default mouse mode popup button. "*/
- (IBAction)mouseModeChanged:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfKitMouseModeKey];
}

/*" This method is connected to default mouse mode popup button. "*/
- (IBAction)colorMapChanged:sender
{

	[SUD setBool:([(NSCell *)sender state]==NSOnState) forKey:PdfColorMapKey];
    [self updateSettingsDependenciesFromDefaults:SUD];
}

- (IBAction)colorParam1Changed:sender
{

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfColorParam1Key];
}

// end mitsu 1.29
#endif



//==============================================================================
- (void)cancelEnginePathDiscovery
{
    self.enginePathSearchGeneration++;
    self.initialEnginePathSearchPending = NO;
    self.enginePathSearchButton.enabled = YES;
    self.enginePathSearchButton = nil;
}

- (void)discoverInitialEnginePaths
{
    [self searchEnginePathsForInitialSetup:YES sender:nil];
}

- (IBAction)discoverEnginePaths:(id)sender
{
    if (![self finishPreferenceEditing:YES]) return;
    [self searchEnginePathsForInitialSetup:NO sender:sender];
}

- (BOOL)enginePathSnapshotMatches:(NSArray<NSString *> *)snapshot initial:(BOOL)initial
{
    if (![snapshot[0] isEqualToString:[SUD stringForKey:TetexBinPath] ?: @""] ||
        ![snapshot[1] isEqualToString:[SUD stringForKey:GSBinPath] ?: @""]) return NO;
    return initial || ([_tetexBinPathField.stringValue isEqualToString:snapshot[0]] &&
                       [_gsBinPathField.stringValue isEqualToString:snapshot[1]]);
}

- (void)searchEnginePathsForInitialSetup:(BOOL)initial sender:(NSButton *)sender
{
    [self cancelEnginePathDiscovery];
    NSUInteger generation = self.enginePathSearchGeneration;
    self.initialEnginePathSearchPending = initial;
    self.enginePathSearchButton = sender;
    sender.enabled = NO;
    NSArray *snapshot = @[[SUD stringForKey:TetexBinPath] ?: @"", [SUD stringForKey:GSBinPath] ?: @""];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *found = [TSEnginePathDiscovery candidatesForPaths:[TSEnginePathDiscovery systemSearchPaths]
                                                  currentTeX:snapshot[0] currentGhostscript:snapshot[1]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.enginePathSearchGeneration) return;
            self.initialEnginePathSearchPending = NO;
            sender.enabled = YES;
            // If Settings opened during the initial search, use its sheet.
            BOOL applyInitial = initial && !self->_prefsWindow.visible;
            if ((!initial && !self->_prefsWindow.visible) || ![self enginePathSnapshotMatches:snapshot initial:applyInitial]) return;
            NSAlert *alert = [NSAlert new];
            alert.messageText = NSLocalizedString(initial ? @"Set Up TeX Engine Paths" : @"Detected Engine Paths", @"");
            BOOL hasPaths = [found[@"TeX"] count] || [found[@"Ghostscript"] count];
            alert.informativeText = NSLocalizedString(@"The newest detected installation is selected. You can choose another candidate below.", @"");
            NSView *choices = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 340)];
            NSMutableDictionary *matrices = [NSMutableDictionary dictionary];
            CGFloat top = 340;
            for (NSString *key in @[@"TeX", @"Ghostscript"]) {
                NSTextField *label = [NSTextField labelWithString:key];
                label.font = [NSFont boldSystemFontOfSize:13];
                top -= 22;
                label.frame = NSMakeRect(0, top, 560, 20);
                [choices addSubview:label];
                NSArray *candidates = found[key];
                if (candidates.count == 0) {
                    NSTextField *missing = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Not found", @"")];
                    top -= 30;
                    missing.frame = NSMakeRect(0, top, 560, 28);
                    [choices addSubview:missing];
                } else {
                    NSButtonCell *cell = [NSButtonCell new];
                    [cell setButtonType:NSButtonTypeRadio];
                    cell.font = [NSFont systemFontOfSize:12];
                    cell.wraps = YES;
                    NSMatrix *matrix = [[NSMatrix alloc] initWithFrame:NSMakeRect(0, 0, 540, 42 * candidates.count)
                        mode:NSRadioModeMatrix prototype:cell numberOfRows:candidates.count numberOfColumns:1];
                    matrix.cellSize = NSMakeSize(540, 40);
                    matrix.intercellSpacing = NSMakeSize(0, 2);
                    [matrix sizeToCells];
                    for (NSUInteger row = 0; row < candidates.count; row++) {
                        NSDictionary *candidate = candidates[row];
                        NSString *version = [candidate[@"version"] length] ? candidate[@"version"] : NSLocalizedString(@"Version unavailable", @"");
                        [[matrix cellAtRow:row column:0] setTitle:[NSString stringWithFormat:@"%@\n%@", version, candidate[@"path"]]];
                        [matrix setToolTip:candidate[@"path"] forCell:[matrix cellAtRow:row column:0]];
                    }
                    [matrix selectCellAtRow:0 column:0];
                    CGFloat height = MIN(126, NSHeight(matrix.frame));
                    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, top - height, 560, height)];
                    scroll.hasVerticalScroller = YES;
                    scroll.autohidesScrollers = YES;
                    scroll.drawsBackground = NO;
                    scroll.documentView = matrix;
                    [matrix scrollCellToVisibleAtRow:0 column:0];
                    [choices addSubview:scroll];
                    matrices[key] = matrix;
                    top -= height;
                }
                top -= 16;
            }
            // Remove unused space when there are only one or two installations.
            for (NSView *view in choices.subviews) [view setFrameOrigin:NSMakePoint(view.frame.origin.x, view.frame.origin.y - top)];
            [choices setFrameSize:NSMakeSize(560, 340 - top)];
            alert.accessoryView = choices;
            if (![found[@"TeX"] count]) alert.informativeText = [alert.informativeText stringByAppendingFormat:@"\n\n%@", NSLocalizedString(@"Install a TeX distribution, then run Auto Setup in Settings > Typesetting.", @"")];
            [alert addButtonWithTitle:NSLocalizedString(hasPaths ? @"Use These Paths" : @"OK", @"")];
            if (hasPaths) [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
            void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
                if (response != NSAlertFirstButtonReturn || !hasPaths || generation != self.enginePathSearchGeneration ||
                    (!applyInitial && !self->_prefsWindow.visible) ||
                    ![self enginePathSnapshotMatches:snapshot initial:applyInitial]) return;
                NSArray *keys = @[TetexBinPath, GSBinPath];
                NSArray *names = @[@"TeX", @"Ghostscript"];
                NSArray *required = @[@[@"tex", @"latex", @"pdftex", @"pdflatex"], @[@"gs"]];
                for (NSUInteger i = 0; i < keys.count; i++) {
                    NSMatrix *matrix = matrices[names[i]];
                    NSString *path = matrix ? found[names[i]][matrix.selectedRow][@"path"] : nil;
                    if (!path || ![TSEnginePathDiscovery directory:path containsPrograms:required[i]]) continue;
                    [SUD setObject:path forKey:keys[i]];
                }
                if (!applyInitial) {
                    self->_tetexBinPathField.stringValue = [SUD stringForKey:TetexBinPath];
                    self->_gsBinPathField.stringValue = [SUD stringForKey:GSBinPath];
                }
            };
            if (applyInitial) finish([alert runModal]);
            else [alert beginSheetModalForWindow:self->_prefsWindow completionHandler:finish];
        });
    });
}

/*" This method is connected to the textField that holds the tetex bin path.
"*/
- (IBAction)tetexBinPathChanged:(id)sender
{
    [self commitPreferenceField:_tetexBinPathField showError:YES reflect:YES];
}

//==============================================================================
/*" This method is connected to the textField that holds the HtmlHome value
"*/
- (IBAction)HtmlHomeChanged:(id)sender
{
    [self commitPreferenceField:_HtmlHomeField showError:YES reflect:YES];
}


//==============================================================================
/*" This method is connected to the textField that holds the alternate path.
"*/
- (IBAction)altPathChanged:(id)sender
{
    [self commitPreferenceField:_altPathField showError:YES reflect:YES];
}


//==============================================================================
/*" This method is connected to the textField that holds the gs bin path.
"*/
- (IBAction)gsBinPathChanged:(id)sender
{
    [self commitPreferenceField:_gsBinPathField showError:YES reflect:YES];
}

//==============================================================================
// TeX pane
//==============================================================================
/*" This method is connected to the textField that holds the TeX command. It is located on the TeX pane.
"*/
- (IBAction)texProgramChanged:(id)sender
{
    [self commitPreferenceField:_texCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the LaTeX command. It is located on the TeX pane.
"*/
- (IBAction)latexProgramChanged:(id)sender
{
    [self commitPreferenceField:_latexCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the tex + ghostscript command. It is located on the TeX pane.
"*/
- (IBAction)texGSProgramChanged:(id)sender
{
    [self commitPreferenceField:_texGSCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the latextex + ghostscript command. It is located on the TeX pane.
"*/
- (IBAction)latexGSProgramChanged:(id)sender
{
    [self commitPreferenceField:_latexGSCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the 'save postscript' checkbox.
"*/
- (IBAction)savePSPressed:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:SavePSEnabledKey];
}

#ifdef USESPARKLE

/*" Sparkle Actions 
"*/
- (IBAction)sparkleAutomaticCheck:sender
{

    
    BOOL theValue = [(NSCell *) sender state];
    
    [SUD setBool:theValue forKey:SparkleAutomaticUpdateKey];
    
    
    [[TSSparkleController sharedUpdater] setAutomaticallyChecksForUpdates: theValue ];
    [self updateSettingsDependenciesForCategory:TSSettingsCategoryUpdates defaults:SUD];
    
}

- (IBAction)sparkleInterval:sender
{

    
    
    [SUD setInteger:[[sender selectedCell] tag] forKey:SparkleIntervalKey];
    
    switch ([[sender selectedCell] tag])
    {
        case 1: [[TSSparkleController sharedUpdater] setUpdateCheckInterval: 86400];
                break;
            
        case 2: [[TSSparkleController sharedUpdater] setUpdateCheckInterval: 604800];
            break;
            
        case 3: [[TSSparkleController sharedUpdater] setUpdateCheckInterval: 2629800];
            break;
    }
 
    
}

#endif







/*" This method is connected to the textField that holds the tex script command. It is located on the TeX pane.
"*/
- (IBAction)texScriptProgramChanged:(id)sender
{
    [self commitPreferenceField:_texScriptCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the latex script command. It is located on the TeX pane.
"*/
- (IBAction)latexScriptProgramChanged:(id)sender
{
    [self commitPreferenceField:_latexScriptCommandTextField showError:YES reflect:YES];
}

/*" This method is connected to the textField that holds the alternate engine command. It is located on the Misc pane.
"*/
- (IBAction)alternateEngineChanged:(id)sender
{
    [self commitPreferenceField:_alternateEngineTextField showError:YES reflect:YES];
}


/*" This method is connected to the "Default Program" matrix on the TeX pane.

A tag of 0 means use TeX, a tag of 1 means use LaTeX.
"*/
- (IBAction)defaultProgramChanged:sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:DefaultCommandKey];
	if ([[sender selectedCell] tag] == 2) {
		[self updateSettingsDependenciesForCategory:TSSettingsCategoryTypesetting defaults:SUD];
		[_engineTextField setEditable: YES];
		[_engineTextField setSelectable: YES];
		[_engineTextField selectText:self];
	}
	else
		[self updateSettingsDependenciesForCategory:TSSettingsCategoryTypesetting defaults:SUD];
}

- (IBAction)setEngine:(id)sender
{
    [self commitPreferenceField:_engineTextField showError:YES reflect:YES];
}

/*" This method is connected to the "Default Script" matrix on the TeX pane.

A tag of 100 means use pdftex, a tag of 101 means use tex + ghostscript, a tag of 102 means use
person script. See also: DefaultTypesetMode.

"*/
- (IBAction)defaultScriptChanged:sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:DefaultScriptKey];
}

- (IBAction)syncChanged: sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:SyncMethodKey];
}



// zenitani 1.35 (C)
- (IBAction)ptexUtfOutputPressed:sender
{

	[SUD setBool:[(NSCell *)sender state] forKey:ptexUtfOutputEnabledKey];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:ptexUtfOutputEnabledKey]];
}

// koch, 4/10/2011
- (IBAction)convertUTFPressed:sender
{
    [SUD setBool:[(NSButton *)sender state] forKey:AutomaticUTF8MACtoUTF8ConversionKey];
 
/*
   self.consoleFont = [NSFont fontWithName: [SUD stringForKey:ConsoleFontNameKey] size:[SUD floatForKey:ConsoleFontSizeKey]];
    
    // become first responder so we will see the envents that NSFontManager sends
    // up the responder chain
    [_prefsWindow makeFirstResponder:_prefsWindow];
    [[NSFontManager sharedFontManager] setSelectedFont:self.consoleFont isMultiple:NO];
 */
}


- (IBAction)openRootFilePressed:sender
{
    
    [SUD setBool:[(NSButton *)sender state] forKey:AutoOpenRootFileKey];
}

- (IBAction)miniaturizeRootFilePressed:sender
{
    
    [SUD setBool:[(NSButton *)sender state] forKey:MiniaturizeRootFileKey];
}

- (void)setSettingsControl:(NSControl *)control enabled:(BOOL)enabled
{
    if (control == nil) return;
    control.enabled = enabled;
    NSView *row = control.superview;
    while (row != nil && ![row.identifier hasPrefix:@"row."]) row = row.superview;
    if (row == nil) return;
    NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:row];
    while (pending.count) {
        NSView *view = pending.lastObject; [pending removeLastObject];
        if ([view isKindOfClass:NSControl.class]) ((NSControl *)view).enabled = enabled;
        [pending addObjectsFromArray:view.subviews];
    }
}
// A rule names its source value, typed outlet and whether the whole row or
// only the accessory depends on it. Per-document defaults have no parent rule.
- (void)updateSettingsDependenciesForCategory:(TSSettingsCategoryID)category defaults:(NSUserDefaults *)defaults
{
    typedef NS_ENUM(NSUInteger, TSDependencyKind) { TSDependencyBoolean, TSDependencyInteger };
    typedef struct {
        __unsafe_unretained TSSettingsCategoryID category;
        __unsafe_unretained TSPreferenceKey key;
        NSInteger enabledValue;
        TSDependencyKind kind;
        __unsafe_unretained id endpoint;
        BOOL wholeRow;
    } Rule;
    Rule rules[] = {
#include "TSSettingsDependencies.inc"
    };
    // These defaults can also be changed on existing documents through menus.
    // Their subordinate values stay editable regardless of the default choice.
    if (category == nil || [category isEqual:TSSettingsCategoryEditor]) {
        [self setSettingsControl:BlockCursorColorWell enabled:YES];
        [self setSettingsControl:_blockSideMatrix enabled:YES];
        [self setSettingsControl:_blockWidthMatrix enabled:YES];
    }
    if (category == nil || [category isEqual:TSSettingsCategoryGeneral]) {
        [self setSettingsControl:useLeftSourceButton enabled:YES];
        [self setSettingsControl:useRightSourceButton enabled:YES];
    }
    for (NSUInteger i = 0; i < sizeof(rules)/sizeof(rules[0]); i++) {
        Rule rule = rules[i];
        if (category && ![category isEqual:rule.category]) continue;
        NSInteger value = rule.kind == TSDependencyBoolean ? [defaults boolForKey:rule.key] : [defaults integerForKey:rule.key];
        BOOL enabled = value == rule.enabledValue;
#ifdef USESPARKLE
        if ([rule.key isEqual:SparkleAutomaticUpdateKey] && defaults == SUD && [TSSparkleController sharedUpdater])
            enabled = [TSSparkleController sharedUpdater].automaticallyChecksForUpdates;
#endif
        [rule.endpoint setEnabled:enabled];
        NSControl *control = [rule.endpoint isKindOfClass:NSCell.class] ? [(NSCell *)rule.endpoint controlView] : rule.endpoint;
        if (rule.wholeRow) [self setSettingsControl:control enabled:enabled];
    }
}
- (void)updateSettingsDependenciesFromDefaults:(NSUserDefaults *)defaults
{
    [self updateSettingsDependenciesForCategory:nil defaults:defaults];
}

- (void)updateSpellingControlsFromDefaults:(NSUserDefaults *)defaults
{
    BOOL enabled = [defaults boolForKey:TSTeXAwareSpellCheckingKey];
    _texAwareSpellCheckButton.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.legacySpellCheckButton != nil) self.legacySpellCheckButton.state = enabled ? NSControlStateValueOff : NSControlStateValueOn;
    // The exclusion rules apply only to TeX-aware spell checking.
    [self updateSettingsDependenciesForCategory:TSSettingsCategorySpelling defaults:defaults];
}

- (IBAction)texAwareSpellCheckPressed:(NSButton *)sender
{
    id previousNoteValue = @([SUD boolForKey:TSTeXAwareSpellCheckingKey]);
    [SUD setBool:(sender.state == NSControlStateValueOn) forKey:TSTeXAwareSpellCheckingKey];
    [self updateSpellingControlsFromDefaults:SUD];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:TSTeXAwareSpellCheckingKey]];
    [self.settingsChangeNotes recordUserChangeForKey:TSTeXAwareSpellCheckingKey previousValue:previousNoteValue];
}

- (IBAction)editKeyBindings:(id)sender
{
    if (self.keyBindingEditor == nil) self.keyBindingEditor = [TSAutoCompletionListEditor new];
    [self.keyBindingEditor openAutoCompletionListEditor:sender];
}

- (IBAction)displayCommentLines:(id)sender
{
    if (self.settingsHelpDocuments == nil) self.settingsHelpDocuments = [HelpDocuments new];
    [self.settingsHelpDocuments displayCommentLines:sender];
}

- (IBAction)legacySpellCheckPressed:(NSButton *)sender
{
    id previousNoteValue = @([SUD boolForKey:TSTeXAwareSpellCheckingKey]);
    [SUD setBool:NO forKey:TSTeXAwareSpellCheckingKey];
    [self updateSpellingControlsFromDefaults:SUD];
    [self applyEffectsForPreferenceKeys:[NSSet setWithObject:TSTeXAwareSpellCheckingKey]];
    [self.settingsChangeNotes recordUserChangeForKey:TSTeXAwareSpellCheckingKey previousValue:previousNoteValue];
}

- (IBAction)editSpellingExclusions:(id)sender
{
    [TSSpellSupport editSpellingExclusions:sender];
}

- (IBAction)spellCheckCommandPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:TurnOffCommandSpellCheckKey];
}

- (IBAction)spellCheckParameterPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state]  forKey:TurnOffParameterSpellCheckKey];
    
}

- (IBAction)spellCheckCommentPressed:sender
{
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state]  forKey:TurnOffCommentSpellCheckKey];
}




/*" This method is connected to the "Console" matrix on the TeX pane.

A tag of 0 means "always", a tag of 1 means "when errors occur".
"*/
- (IBAction)consoleBehaviorChanged:sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:ConsoleBehaviorKey];
}

- (IBAction)dictionaryPressed: sender
{
    
    NSString *language = [[sender selectedItem] title];
    
    
    
    if ([language isEqualToString: @"Automatic Language"])
    {
        [SUD setBool:YES forKey:spellingAutomaticDefaultKey];
        [SUD setObject:@" " forKey:spellingLanguageDefaultKey];
    }
    else
    {
        [SUD setBool:NO forKey:spellingAutomaticDefaultKey];
        [SUD setObject:language forKey:spellingLanguageDefaultKey];
    }
    
}


/*" This method is connected to the "After Typesetting" matrix on the Preference pane.
A tag of 0 means "Activate Preview"; a tag of 1 means "Continue Editing".
"*/
- (IBAction)afterTypesettingChanged:sender;
{
	BOOL newBoolValue;
    NSInteger newValue;
	NSInteger		tagValue;
	

	tagValue = [[sender selectedCell] tag];
    
    if (tagValue == 1)
		newBoolValue = NO;
	else
		newBoolValue = YES;
    
    newValue = tagValue;
    if (newValue > 2)
        newValue = 0;
    
    
	[SUD setBool:newBoolValue forKey:BringPdfFrontOnTypesetKey];
    [SUD setInteger:newValue forKey: BringFrontOnTypesetKey];
    
}

/*" This method is connected to the "Console" matrix on the TeX pane.

A tag of 0 means "always", a tag of 1 means "when errors occur".
"*/
- (IBAction)saveRelatedButtonPressed:sender
{

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setBool:[(NSCell *)sender state] forKey:SaveRelatedKey];
}

- (IBAction)useTransparencyPressed:sender
{

    // since the default program values map identically to the tags of the NSButtonCells,
    // we can use the tag directly here.
    [SUD setBool:[(NSCell *)sender state] forKey:UseTransparencyKey];
}

/*" On Typesetting Pane

A tag of 0 means "no", a tag of 1 means "yes".
"*/
- (IBAction)syncTabButtonPressed:sender
{

    // since the default program values map identically to the tags of the NSButtonCells,
    // we can use the tag directly here.
    [SUD setBool:[(NSCell *)sender state] forKey:SyncUseTabsKey];
}


//==============================================================================
// other target/action methods
//==============================================================================
/*" This method is connected to the OK button.
"*/


/*" This method is connected to the Cancel button.
"*/


//==============================================================================
// notification methods
//==============================================================================
/*" This method will be called whenever the user defaults change. We simply update the state of the prefences window and all of its controls. This may sound like the "brute force" method (in fact it is) but since the UserDefaults aren't likely to change from outside of this class we'll ignore that for now.
"*/
/*" Actually, Feb 26, 2009, I discovered that this routine is often called, including at terminate time when some objects it calls may already be disposed! 
 I have no idea why we'd ever want to call this routine. Note that updateControlsFromUserDefaults is called by showPreferences, so since this only calls it when
 the window is not visible, and it will be called again when it becomes visible, I don't see what point! RMK"*/
- (void)userDefaultsChanged:(NSNotification *)notification
{
	// only update the window's controls when the window is not visible.
	// If the window is visible the user edits it directly with the mouse.
	if ([_prefsWindow isVisible] == NO) {
		// [self updateControlsFromUserDefaults:[notification object]];
	}
}

//==============================================================================
// API used by other TeXShop classes
//==============================================================================

/*" This method returns a relative path name of 'path', based on fromFile: file. If the second argument 'file' is nil, it will return an absolute path of 'path'. Added by zenitani, Feb 13, 2003. "*/
- (NSString *)relativePath: (NSString *)path fromFile: (NSString *)file
{
	NSArray *a, *b;
	NSString *rpath = @"", *astr, *bstr;

	a = [[ file stringByDeletingLastPathComponent ] pathComponents ];
	b = [ path pathComponents ];
	NSUInteger ai = [a count], bi = [b count], i, j;
	if( ai == 0 ) return path;
	for( i=0; ((i<ai)&&(i<bi)); i++ ){
		astr = [a objectAtIndex: i];
		bstr = [b objectAtIndex: i];
		if( [astr compare: bstr] != NSOrderedSame )  break;
	}
//    NSLog( @"%d %d %d", ai, bi, i );
	for( j=0; j<(ai-i); j++ ){
		rpath = [rpath stringByAppendingString: @"../"];
//        NSLog( @"%@\n", rpath );
	}
	for( j=i; j<bi-1; j++ ){
		rpath = [rpath stringByAppendingFormat: @"%@/", [b objectAtIndex: j]];
//        NSLog( @"%@\n", rpath );
	}
	rpath = [rpath stringByAppendingFormat: @"%@", [b objectAtIndex: (bi-1)]];
	return rpath;
}


/*" This method will be called when no defaults were registered so far. Since this is the first time that TeXShop runs, we register a standard defaults set (from the FactoryDefaults.plist) and fill ~/Library/TeXShop/Templates with our templates.
"*/
- (void)registerFactoryDefaults
{
	NSString *fileName;
	NSDictionary *factoryDefaults;
    NSStringEncoding theEncoding;

	// register defaults
	fileName = [[NSBundle mainBundle] pathForResource:@"FactoryDefaults" ofType:@"plist" inDirectory:@"Defaults"];
	NSParameterAssert(fileName != nil);
	factoryDefaults = [[NSString stringWithContentsOfFile:fileName usedEncoding: &theEncoding error: NULL] propertyList];

	[SUD setPersistentDomain:factoryDefaults forName:TSPreferencesDomainName()];
	[SUD synchronize]; /* added by Koch Feb 19, 2001 to fix pref bug when no defaults present */

	// also register the default font. documentFont was set in -init, dump it here to
	// the user defaults
	[SUD setObject:[NSArchiver archivedDataWithRootObject:self.documentFont] forKey:DocumentFontKey];
    [SUD setObject:[NSArchiver archivedDataWithRootObject:self.fontAttributes] forKey:DocumentFontAttributesKey];
	[SUD synchronize];
}

- (void)addPreferenceField:(NSControl *)field rule:(TSPreferenceInput *)rule
{
    if (field == nil) return;
    [self.inputRules setObject:rule forKey:field];
    // The common validator owns both regular editing and no-UI termination.
    // A whole-number field only keeps its typing to digits and carries its
    // range for the stepper beside it.
    field.formatter = rule.kind == TSPreferenceInputInteger ? [[TSIntegerInputFormatter alloc] initWithInput:rule] : nil;
    if ([field isKindOfClass:NSTextField.class]) ((NSTextField *)field).delegate = self;
}
- (void)configurePreferenceInputs
{
    self.inputRules = [NSMapTable strongToStrongObjectsMapTable];
    self.inputEditing = [TSPreferenceEditing new];
    [self addPreferenceField:tabIndentField rule:[[TSPreferenceInput alloc] initWithKey:tabsKey
        kind:TSPreferenceInputInteger minimum:TSTabWidthRange.minimum maximum:TSTabWidthRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(tabsKey)]];
    [self addPreferenceField:firstParagraphIndentField rule:[[TSPreferenceInput alloc] initWithKey:SourceFirstLineHeadIndentKey
        kind:TSPreferenceInputInteger minimum:TSParagraphIndentRange.minimum maximum:TSParagraphIndentRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(SourceFirstLineHeadIndentKey)]];
    [self addPreferenceField:remainingParagraphIndentField rule:[[TSPreferenceInput alloc] initWithKey:SourceHeadIndentKey
        kind:TSPreferenceInputInteger minimum:TSParagraphIndentRange.minimum maximum:TSParagraphIndentRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(SourceHeadIndentKey)]];
    [self addPreferenceField:interlineSpacingField rule:[[TSPreferenceInput alloc] initWithKey:SourceInterlineSpaceKey
        kind:TSPreferenceInputInteger minimum:TSInterlineSpaceRange.minimum maximum:TSInterlineSpaceRange.maximum allowsEmpty:NO notification:TSPreferenceNotificationForKey(SourceInterlineSpaceKey)]];
    [self addPreferenceField:_magTextField rule:[[TSPreferenceInput alloc] initWithKey:PdfMagnificationKey
        kind:TSPreferenceInputPercentage minimum:20 maximum:400 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_HtmlHomeField rule:[[TSPreferenceInput alloc] initWithKey:HtmlHomeKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
    [self addPreferenceField:_engineTextField rule:[[TSPreferenceInput alloc] initWithKey:DefaultEngineKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_texCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:TexCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_latexCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:LatexCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_texGSCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:TexGSCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_latexGSCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:LatexGSCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_tetexBinPathField rule:[[TSPreferenceInput alloc] initWithKey:TetexBinPath
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_gsBinPathField rule:[[TSPreferenceInput alloc] initWithKey:GSBinPath
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_altPathField rule:[[TSPreferenceInput alloc] initWithKey:AltPathKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
    [self addPreferenceField:_kpsetoolField rule:[[TSPreferenceInput alloc] initWithKey:KpsetoolKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_bibTeXengineField rule:[[TSPreferenceInput alloc] initWithKey:BibTeXengineKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil]];
    [self addPreferenceField:_texScriptCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:TexScriptCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
    [self addPreferenceField:_latexScriptCommandTextField rule:[[TSPreferenceInput alloc] initWithKey:LatexScriptCommandKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
    [self addPreferenceField:_alternateEngineTextField rule:[[TSPreferenceInput alloc] initWithKey:AlternateEngineKey
        kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil]];
}

- (void)showPreferenceError:(NSString *)message
{
    if (self.endingPreferences || _prefsWindow == nil || _prefsWindow.attachedSheet != nil) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Settings could not be saved", @"");
    alert.informativeText = message;
    [alert beginSheetModalForWindow:_prefsWindow completionHandler:nil];
}
- (void)presentInputErrorForField:(NSControl *)field
{
    if (self.inputErrorPresented || self.endingPreferences || _prefsWindow.attachedSheet != nil) return;
    self.inputErrorPresented = YES;
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Enter a valid setting", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Continue Editing", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Restore This Field", @"")];
    TSPreferenceInput *rule = [self.inputRules objectForKey:field];
    if (rule == nil) { self.inputErrorPresented = NO; return; }
    __weak TSPreferences *weakSelf = self;
    [alert beginSheetModalForWindow:_prefsWindow completionHandler:^(NSModalResponse response) {
        TSPreferences *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        strongSelf.inputErrorPresented = NO;
        if (strongSelf.endingPreferences) return;
        if (response == NSAlertSecondButtonReturn) {
            [strongSelf.inputEditing restoreField:field rule:rule defaults:SUD];
        }
    }];
}
- (BOOL)commitPreferenceField:(NSControl *)field showError:(BOOL)showError reflect:(BOOL)reflect
{
    if (field == nil) return YES;
    TSPreferenceInput *rule = [self.inputRules objectForKey:field];
    if (rule == nil) return YES;
    id previousNoteValue = [self.settingsChangeNotes currentValueForKey:rule.key] ?: NSNull.null;
    BOOL valid = [self.inputEditing commitField:field rule:rule defaults:SUD reflect:reflect sender:self];
    if (valid && !self.endingPreferences) [self.settingsChangeNotes recordUserChangeForKey:rule.key previousValue:previousNoteValue];
    if (!valid && showError) [self presentInputErrorForField:field];
    return valid;
}
- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
    NSControl *field = notification.object;
    if ([self.inputRules objectForKey:field] != nil) [self.inputEditing markEdited:field];
}
- (void)controlTextDidChange:(NSNotification *)notification
{
    [self controlTextDidBeginEditing:notification];
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)editor
{
    return [self commitPreferenceField:control showError:YES reflect:YES];
}
- (BOOL)finishPreferenceEditing:(BOOL)showError
{
    if (showError && _prefsWindow.attachedSheet != nil) return NO;
    BOOL valid = YES;
    for (NSControl *field in self.inputRules) {
        if (field.currentEditor != nil && ![self commitPreferenceField:field showError:showError reflect:showError]) {
            valid = NO;
            if (showError) return NO;
        }
    }
    if (showError) return [_prefsWindow makeFirstResponder:nil];
    return valid;
}
- (BOOL)windowShouldClose:(NSWindow *)window
{
    return window != _prefsWindow || [self finishPreferenceEditing:YES];
}
- (void)windowWillClose:(NSNotification *)notification
{
    if (notification.object == _prefsWindow) [self tearDownPreferenceEditing];
}
- (void)setAllThemeEditingEnabled:(BOOL)enabled
{
    // A category can be detached from the window while its controls still exist.
    NSView *appearance = [self.settingsController viewForCategoryIdentifier:TSSettingsCategoryAppearance];
    if (appearance != nil) [self setThemeEditingEnabled:enabled inView:appearance];
    for (TSPrefPaneController *pane in self.preferencePanes) [self setThemeEditingEnabled:enabled inView:pane.view];
}
- (void)releasePreferencePanels
{
    [self deactivatePreferenceColorWells];
    NSFontManager *manager = [NSFontManager sharedFontManager];
    if (self.ownsFontPanel && manager.target == nil &&
        (_prefsWindow.isKeyWindow || _prefsWindow.isMainWindow)) {
        [[manager fontPanel:NO] close];
    }
    self.ownsFontPanel = NO;
    self.fontEditingContext = TSSettingsFontNone;
}
- (void)tearDownPreferenceEditing
{
    self.endingPreferences = YES;
    self.themeOperationGeneration++;
    if (_prefsWindow.attachedSheet != nil) [_prefsWindow endSheet:_prefsWindow.attachedSheet returnCode:NSModalResponseCancel];
    [self cancelEnginePathDiscovery];
    [self releasePreferencePanels];
    [self.inputEditing clear];
    [self.settingsController endSession];
}
- (void)finishPreferencesForTermination
{
    self.endingPreferences = YES;
    self.themeOperationGeneration++;
    if (_prefsWindow.attachedSheet != nil) [_prefsWindow endSheet:_prefsWindow.attachedSheet returnCode:NSModalResponseCancel];
    [self finishPreferenceEditing:NO];
    // Do not invoke formatter delegates or actions that could display a sheet.
    for (NSControl *field in self.inputRules) [field abortEditing];
    [self tearDownPreferenceEditing];
}

//==============================================================================
// helpers
//==============================================================================

/*"  %{This method is not to be called from outside of this class.}

This method retrieves the application preferences from the defaults object and sets the controls in the window accordingly.
"*/
#include "TSSettingsPaneRefresh.inc"

/*" %{This method is not to be called from outside of this class}

This method updates the textField that represents the name of the selected font in the Document pane.
"*/
- (void)updateDocumentFontTextField
{
	NSString *fontDescription;

	fontDescription = [NSString stringWithFormat:@"%@ - %2.0f", [self.documentFont displayName], [self.documentFont pointSize]];
	[_documentFontTextField setStringValue:fontDescription];
}

- (void)updateConsoleFontTextField
{
	NSString *fontDescription;

	fontDescription = [NSString stringWithFormat:@"%@ - %2.0f", [SUD stringForKey:ConsoleFontNameKey], [SUD floatForKey:ConsoleFontSizeKey]];
	[_consoleFontTextField setStringValue:fontDescription];
}




/*" %{This method is not to be called from outside of this class.} "*/


@end
