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

#import "UseMitsu.h"
#import "UseSparkle.h"

#import "TSPreferences.h"
#import "TSEnginePathDiscovery.h"
#import "TSInvisibleCharacters.h"
#import "TSDockIconController.h"
#import "TSKeyboardShortcuts.h"
#import "TSSpellSupport.h"
#import "TSWindowManager.h"
#import "TSEncodingSupport.h"
#import "globals.h"
#import "TSPreviewWindow.h"
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


@interface TSPreferences ()
@property NSUInteger enginePathSearchGeneration;
@property BOOL initialEnginePathSearchPending;
@property (weak) NSButton *enginePathSearchButton;
- (void)searchEnginePathsForInitialSetup:(BOOL)initial sender:(NSButton *)sender;
- (void)refreshRuntimePreferences;
@end

@implementation TSPreferences
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
	_undoManager = [[NSUndoManager alloc] init];
	// setup the default font here so it's defined when we run for the first time.
	self.documentFont = [NSFont userFontOfSize:12.0];
    self.fontAttributes = nil;
	// self.consoleFont = [NSFont userFixedPitchedFontOfSize:10.0];

	// register for changes in the user defaults
	
	// I now believe this is not needed; Feb 24, 2009 RMK
	// [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];

	return self;
}

/*
- (void)dealloc
{
	[_undoManager release];
	[super dealloc];
}
*/

//==============================================================================
// target/action methods
//==============================================================================
/*" Connected to the "Preferences..." menu item in Application's main menu.

Loads the .nib file if necessary, fills all the controls with the values from the user defaults and makes the window visible.
"*/
- (IBAction)showPreferences:sender
{
    if (_prefsWindow.visible) {
        [_prefsWindow makeKeyAndOrderFront:sender];
        return;
    }
    if (!self.initialEnginePathSearchPending) [self cancelEnginePathDiscovery];
	if (_prefsWindow == nil) {
		// we need to load the nib
		if ([NSBundle loadNibNamed:@"Preferences" owner:self] == NO) {
			NSRunAlertPanel(@"Error", @"Could not load Preferences.nib", @"shit happens", nil, nil);
		}

		// fill in all the values here since the window will be brought up for the first time
		/* koch: I moved this command two lines below, so it will ALWAYS be called
		when showing preferences: [self updateControlsFromUserDefaults:SUD]; */
	}

	[SUD synchronize];

    [[TSDockIconController sharedController] installInPreferences:_tabView];
    [[TSDockIconController sharedController] beginEditing];
    [self updateControlsFromUserDefaults:SUD];
    [self PrepareColorPane:SUD];
    
    //_sourceBackgroundColorWell.enabled = NO;
    //_sourceBackgroundColorWell.highlighted = NO;
    //_sourceTextColorWell.enabled = NO;
    
	/* the next command causes windows to remember their font in case it is changed, and then
	the change is cancelled */
	[[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontRememberNotification object:self];
	[[NSNotificationCenter defaultCenter] postNotificationName:MagnificationRememberNotification object:self];
	fontTouched = NO;
	consoleFontTouched = NO;
	consoleBackgroundColorTouched = NO;
	consoleForegroundColorTouched = NO;
	sourceBackgroundColorTouched = NO;
    sourceTextColorTouched = NO;
	previewBackgroundColorTouched = NO;
	externalEditorTouched = NO;
	syntaxColorTouched = NO;
    syntaxColorLineTouched = NO;
	oldSyntaxColor = [SUD boolForKey:SyntaxColoringEnabledKey];
    oldSyntaxLineColor = [SUD boolForKey:SyntaxColorEntryLineKey];
	autoCompleteTouched = NO;
	bibDeskCompleteTouched = NO;
    HtmlHomeTouched = NO;
	oldAutoComplete = [SUD boolForKey:AutoCompleteEnabledKey];
	oldBibDeskComplete = [SUD boolForKey:BibDeskCompletionKey];
    magnificationTouched = NO;
	// added by mitsu --(G) TSEncodingSupport
	encodingTouched = NO;
	commandCompletionCharTouched = NO;
	highlightTouched = NO; // added by Terada
	invisibleCharacterTouched = NO; // added by Terada
	kpsetoolTouched = NO; // added by Terada
	bibTeXengineTouched = NO; // added by Terada
	makeatletterTouched = NO; // added by Terada
    sparkleTouched = NO;
#ifdef USESPARKLE
    // Added by Terada: snapshot both updater settings once for Cancel.
    oldSparkleAutomaticUpdate = [TSSparkleController sharedUpdater].automaticallyChecksForUpdates;
    oldSparkleInterval = [TSSparkleController sharedUpdater].updateCheckInterval;
#endif
	// end addition
	// prepare undo manager: forget all the old undo information and begin a new group.
	[_undoManager removeAllActions];
	[_undoManager beginUndoGrouping];

	[_prefsWindow makeKeyAndOrderFront:self];
    

}

//==============================================================================
// Entire panel
//==============================================================================
/*" This method is connected to the 'Set Defaults' menu


"*/

//-----------------------------------
- (void)undoDefaultPrefs:(NSDictionary *)oldDefaults;
//-----------------------------------
{
    BOOL oldTeXAwareSpelling = [SUD boolForKey:@"TeXAwareSpellChecking"];
    BOOL oldMakeatletter = [SUD boolForKey:MakeatletterEnabledKey];
	[SUD setPersistentDomain:oldDefaults forName:TSPreferencesDomainName()];
	[SUD synchronize];
	[self updateControlsFromUserDefaults:SUD];
    if (oldTeXAwareSpelling != [SUD boolForKey:@"TeXAwareSpellChecking"])
        [TSSpellSupport preferencesDidChange];
    // Open documents color commands again when @ is no longer, or now, part of their names.
    if (oldMakeatletter != [SUD boolForKey:MakeatletterEnabledKey])
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NeedsForRecolorNotification" object:self];
    
    // KOCH
    // Here is the spot where we need to redraw the document and console with the remembered fonts
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:ConsoleFontChangedNotification object:self];
    [self refreshRuntimePreferences];
}


- (IBAction)setDefaults:sender
{
    BOOL oldTeXAwareSpelling = [SUD boolForKey:@"TeXAwareSpellChecking"];
    BOOL oldMakeatletter = [SUD boolForKey:MakeatletterEnabledKey];

	NSString *fileName;
	NSDictionary *factoryDefaults, *oldDefaults;
    NSStringEncoding theEncoding;

	// Remember only TeXShop's own persistent domain. dictionaryRepresentation also
	// contains NSGlobalDomain and the registered defaults, which Cancel (through
	// undoDefaultPrefs:) then wrote into TeXShop's domain.
	oldDefaults = [SUD persistentDomainForName:TSPreferencesDomainName()] ?: @{};
	[_undoManager registerUndoWithTarget:self selector:@selector(undoDefaultPrefs:) object:oldDefaults];

	// register defaults
	switch ([sender tag]) {
		case 1: fileName = [[NSBundle mainBundle] pathForResource:@"FactoryDefaults" ofType:@"plist"]; break;
		case 2: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_upTeX_ptex2pdf" ofType:@"plist"]; break;
		case 3: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_upTeX_latexmk" ofType:@"plist"]; break;
		case 4: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_upTeX_script" ofType:@"plist"]; break;
		case 5: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_ptex2pdf" ofType:@"plist"]; break;
		case 6: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_latexmk" ofType:@"plist"]; break;
		case 7: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_script" ofType:@"plist"]; break;
		case 8: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_sjis" ofType:@"plist"]; break;
		case 9: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_euc" ofType:@"plist"]; break;
			/*
			 case 2: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_Inoue" ofType:@"plist"]; break;
			 case 3: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_Kiriki" ofType:@"plist"]; break;
			 case 4: fileName = [[NSBundle mainBundle] pathForResource:@"Defaults_pTeX_Ogawa" ofType:@"plist"]; break;
				 */
		default: fileName = [[NSBundle mainBundle] pathForResource:@"FactoryDefaults" ofType:@"plist"]; break;
	}
	NSParameterAssert(fileName != nil);
	factoryDefaults = [[NSString stringWithContentsOfFile:fileName usedEncoding: &theEncoding error:NULL] propertyList];

	// A profile replaces the settings of this window, but not what is kept elsewhere:
	// the keyboard shortcuts of their own window, the App Shortcuts and app language chosen
	// in System Settings, what Sparkle records about updates (its keys begin with SU), and
	// the positions of windows, toolbars and split views that AppKit saves. The menus keep
	// those shortcuts until TeXShop quits.
	NSMutableDictionary *profile = [NSMutableDictionary dictionaryWithDictionary:factoryDefaults ?: @{}];
	[oldDefaults enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
		if (! [key isKindOfClass:[NSString class]] || profile[key] != nil)
			return;
		if ([key isEqualToString:TSMenuShortcutOverridesKey] || [key isEqualToString:@"NSUserKeyEquivalents"] ||
				[key isEqualToString:@"AppleLanguages"] || [key hasPrefix:@"SU"] || [key hasPrefix:@"NSWindow Frame "] ||
				[key hasPrefix:@"NSToolbar Configuration "] || [key hasPrefix:@"NSSplitView Subview Frames "])
			profile[key] = value;
	}];
	[SUD setPersistentDomain:profile forName:TSPreferencesDomainName()];
	[SUD synchronize]; /* added by Koch Feb 19, 2001 to fix pref bug when no defaults present */

	// also register the default font. _documentFont was set in -init, dump it here to
	// the user defaults
	[SUD setObject:[NSArchiver archivedDataWithRootObject:self.documentFont] forKey:DocumentFontKey];
    if (self.fontAttributes == nil)
        [SUD setObject: nil forKey:DocumentFontAttributesKey];
    else
        [SUD setObject:[NSArchiver archivedDataWithRootObject:self.fontAttributes] forKey:DocumentFontAttributesKey];
	// [SUD setObject:[NSArchiver archivedDataWithRootObject:self.consoleFont] forKey:ConsoleFontKey];
	[SUD synchronize];

	[self updateControlsFromUserDefaults:SUD];
    if (oldTeXAwareSpelling != [SUD boolForKey:@"TeXAwareSpellChecking"])
        [TSSpellSupport preferencesDidChange];
    if (oldMakeatletter != [SUD boolForKey:MakeatletterEnabledKey])
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NeedsForRecolorNotification" object:self];
    
    // KOCH
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontRememberNotification object:self];
    self.documentFont = [NSFont userFontOfSize:12.0];
    [self updateDocumentFontTextField];
    [SUD setObject:[NSArchiver archivedDataWithRootObject:self.documentFont] forKey:DocumentFontKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];
    
    [self updateConsoleFontTextField];
    self.consoleFont = [NSFont fontWithName: [SUD stringForKey:ConsoleFontNameKey] size:[SUD floatForKey:ConsoleFontSizeKey]];
    [SUD setObject: [self.consoleFont fontName] forKey:ConsoleFontNameKey];
    [SUD setFloat: [self.consoleFont pointSize] forKey: ConsoleFontSizeKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:ConsoleFontChangedNotification object:self];
    [self refreshRuntimePreferences];
}


// Refresh the process-wide copies after a group of settings has changed.
// Individual controls update their own copy at the point of persistence.
- (void)refreshRuntimePreferences
{
    editorCanAddBrackets = [SUD boolForKey:EditorCanAddBracketsKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
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
    // fontTouched = YES;
    [_prefsWindow makeFirstResponder:_prefsWindow];
    [[NSFontManager sharedFontManager] setSelectedFont:self.documentFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

// Below was part of an attempt to set additional attributes of the source panel. This was a failure.
// So we retreat to the original method.

/*
- (IBAction)changeDocumentFont:sender
{
    
    
	// become first responder so we will see the events that NSFontManager sends
	// up the responder chain
    
    NSData    *fontData;
    NSFont     *font;
    NSRange myRange;
    NSUInteger thelength;
    
    
    
    if ([[_fontTextView string] isEqualToString:@"Hello"])
        {
        thelength = [[_fontTextView string] length];
        myRange.location = 0;
        myRange.length = thelength;
        [_fontTextView replaceCharactersInRange:myRange withString: NSLocalizedString(@"Type sample text here.\nUse several lines to test\ninterline spacing.", @"Type sample text here.\nUse several lines to test\ninterline spacing.") ];
        }
    
    NSDictionary *fontAttributes =  [NSDictionary dictionary];
    NSMutableAttributedString *myAttributedString;
    myAttributedString = _fontTextView.textStorage;
    thelength = [myAttributedString length];
    if (thelength > 0)
    {
        myRange.location = 0;
        myRange.length = thelength;
        [myAttributedString setAttributes: fontAttributes range: myRange];
    }
    [_fontTextView setTypingAttributes: fontAttributes];

    
    {
        fontData = [SUD objectForKey:DocumentFontKey];
        if (fontData != nil)
        {
            font = [NSUnarchiver unarchiveObjectWithData:fontData];
            [_fontTextView setFont: font];
        }
    }
    
    [_fontTextView setTextColor: NSColor.textColor];
    [_fontTextView  setBackgroundColor: NSColor.textBackgroundColor];
    */

// the next section was commented out even when the original code with a sample window was
// active; this code was a central part of the failed attempt to set attributes
     /*
     
     NSDictionary *fontAttributes;
     NSFontManager *fontManager;
     NSData    *attributesData;
     
     
     NSTextStorage* textViewContent = [_fontTextView textStorage];
    NSRange area = NSMakeRange(0, [textViewContent length]);
    [textViewContent invalidateAttributesInRange:area];

    
      attributesData = [SUD objectForKey:DocumentFontAttributesKey];
     if (attributesData != nil)
     {
 //    NSLog(@"got here");
     fontAttributes = [NSUnarchiver unarchiveObjectWithData:attributesData];
     if (fontAttributes != nil)
     {
  //   NSLog(@"and here");
     myAttributedString = _fontTextView.textStorage;
     thelength = [myAttributedString length];
     myRange.location = 0;
     myRange.length = thelength;
     NSRange area = NSMakeRange(0, thelength);
     [myAttributedString setAttributes: fontAttributes range: area];
     }
     }
     */
/*
 [NSApp beginSheet: _samplePanel
       modalForWindow: _prefsWindow
        modalDelegate: self
       didEndSelector: @selector(didEndSheet:returnCode:contextInfo:)
          contextInfo: nil];

	[_prefsWindow makeFirstResponder:_prefsWindow];
	[[NSFontManager sharedFontManager] setSelectedFont:self.documentFont isMultiple:NO];
	[[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (IBAction)closeSamplePanel: (id)sender
{
    NSData  *fontData;
    
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:DocumentFontKey] forKey:DocumentFontKey];
   // [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:DocumentFontAttributesKey] forKey:DocumentFontAttributesKey];
    
    NSDictionary *newTypingAttributes = _fontTextView.typingAttributes;
    self.fontAttributes = newTypingAttributes;
    self.documentFont = _fontTextView.font;
    fontTouched = YES;
    [self updateDocumentFontTextField];
    
    // update the userDefaults
    fontData = [NSArchiver archivedDataWithRootObject:self.documentFont];
    [SUD setObject:fontData forKey:DocumentFontKey];
    [SUD setBool:YES forKey:SaveDocumentFontKey];
   // FontAttributesData = [NSArchiver archivedDataWithRootObject:self.fontAttributes];
   // [SUD setObject:FontAttributesData forKey:DocumentFontAttributesKey];
    
    
    // post a notification so all open documents can change their font
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];
    
    [NSApp endSheet:_samplePanel];
//    [self changeFont: [NSFontManager sharedFontManager]];
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:self];
}
 */

// We leave the code below present so IB files need not be changed
// this code will never be called
- (IBAction)closeSamplePanel: (id)sender
{
    [NSApp endSheet:_samplePanel];
}

- (IBAction)changeConsoleResize:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:ConsoleWidthResizeKey] forKey:ConsoleWidthResizeKey];
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
	[_prefsWindow makeFirstResponder:_prefsWindow];
	[[NSFontManager sharedFontManager] setSelectedFont:self.consoleFont isMultiple:NO];
	[[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}



/*" This method is sent down the responder chain by the font manager when changing fonts in the font panel. Since this class is delegate of the Window, we will receive this method and we can reflect the changes in the textField accordingly.
"*/
- (void)changeFont:(id)fontManager
{
    
    NSData    *fontData;
    NSString *theTab = [[_tabView selectedTabViewItem] identifier];

	if ([theTab isEqualToString: @"Document"])
		{

		self.documentFont = [fontManager convertFont:self.documentFont];
		fontTouched = YES;

		// register the undo message first
		[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:DocumentFontKey] forKey:DocumentFontKey];

		[self updateDocumentFontTextField];

		// update the userDefaults
		fontData = [NSArchiver archivedDataWithRootObject:self.documentFont];
		[SUD setObject:fontData forKey:DocumentFontKey];
		[SUD setBool:YES forKey:SaveDocumentFontKey];

		// post a notification so all open documents can change their font
		[[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];

		}
		
	else if ([theTab isEqualToString: @"Console"])
		{
		self.consoleFont = [fontManager convertFont:self.consoleFont];
		[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:ConsoleFontNameKey] forKey:ConsoleFontNameKey];
		[[_undoManager prepareWithInvocationTarget:SUD] setFloat:[SUD floatForKey:ConsoleFontSizeKey] forKey:ConsoleFontSizeKey];
		[SUD setObject: [self.consoleFont fontName] forKey:ConsoleFontNameKey];
		[SUD setFloat: [self.consoleFont pointSize] forKey: ConsoleFontSizeKey];
		[self updateConsoleFontTextField];
		consoleFontTouched = YES;
		[[NSNotificationCenter defaultCenter] postNotificationName:ConsoleFontChangedNotification object:self];
		}
}

/*" This method is connected to the "Source Window Position" Matrix.

This method will be called when the matrix changes. Target 0 means 'all windows start at a fixed position', target 1 means 'remember window position'.
"*/
- (IBAction)sourceWindowPosChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:DocumentWindowPosModeKey] forKey:DocumentWindowPosModeKey];

	[SUD setInteger:[[sender selectedCell] tag] forKey:DocumentWindowPosModeKey];
	if ([[sender selectedCell] tag] == 0)
		[_docWindowPosButton setEnabled: YES];
	else
		[_docWindowPosButton setEnabled: NO];
}

/*" This method is connected to the 'use current pos as default' button on the 'Document' pane.
"*/
- (IBAction)currentDocumentWindowPosDefault:sender
{
	NSWindow	*activeWindow;

	activeWindow = [[TSWindowManager sharedInstance] activeTextWindow];

	if (activeWindow != nil) {
		[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:DocumentWindowFixedPosKey] forKey:DocumentWindowFixedPosKey];
		[SUD setObject:[activeWindow stringWithSavedFrame] forKey:DocumentWindowFixedPosKey];

		// just in case: the radio button must be checked as well.
		/* koch: the code below is harmless but probably unnecessary since the button can only
			be pressed if the radio button is in the fixed position mode */
		[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:DocumentWindowPosModeKey] forKey:DocumentWindowPosModeKey];
		[SUD setInteger:DocumentWindowPosFixed forKey:DocumentWindowPosModeKey];
		[_sourceWindowPosMatrix selectCellWithTag:DocumentWindowPosFixed];
	}
}

// added by Terada( - (IBAction)highlightChanged: )
- (IBAction)highlightChanged:(id)sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:AlwaysHighlightEnabledKey] forKey:AlwaysHighlightEnabledKey];
	[SUD setBool:![_alwaysHighlightButton state] forKey:AlwaysHighlightEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:ShowIndicatorForMoveEnabledKey] forKey:ShowIndicatorForMoveEnabledKey];
	[SUD setBool:[_showIndicatorForMoveButton state] forKey:ShowIndicatorForMoveEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:HighlightContentEnabledKey] forKey:HighlightContentEnabledKey];
	[SUD setBool:[_highlightContentButton state] forKey:HighlightContentEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:BeepEnabledKey] forKey:BeepEnabledKey];
	[SUD setBool:[_beepButton state] forKey:BeepEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:FlashBackgroundEnabledKey] forKey:FlashBackgroundEnabledKey];
	[SUD setBool:[_flashBackgroundButton state] forKey:FlashBackgroundEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:CheckBraceEnabledKey] forKey:CheckBraceEnabledKey];
	[SUD setBool:[_checkBraceButton state] forKey:CheckBraceEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:CheckBracketEnabledKey] forKey:CheckBracketEnabledKey];
	[SUD setBool:[_checkBracketButton state] forKey:CheckBracketEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:CheckSquareBracketEnabledKey] forKey:CheckSquareBracketEnabledKey];
	[SUD setBool:[_checkSquareBracketButton state] forKey:CheckSquareBracketEnabledKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:CheckParenEnabledKey] forKey:CheckParenEnabledKey];
	[SUD setBool:[_checkParenButton state] forKey:CheckParenEnabledKey];
	
	highlightTouched = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:@"NeedsForRecolorNotification" object: self];
}

- (void)updateInvisibleCharacterControls:(NSUserDefaults *)defaults
{
    NSArray *popups = @[_SpaceCharacterKindPopup, _FullwidthSpaceCharacterKindPopup,
                        _NewLineCharacterKindPopup, _TabCharacterKindPopup];
    NSArray *buttons = @[_showSpaceCharacterButton, _showFullwidthSpaceCharacterButton,
                         _showNewLineCharacterButton, _showTabCharacterButton];
    NSArray *keys = @[SpaceCharacterKindKey, FullwidthSpaceCharacterKindKey,
                      NewLineCharacterKindKey, TabCharacterKindKey];
    NSArray *showKeys = @[showSpaceCharacterKey, showFullwidthSpaceCharacterKey,
                          showNewLineCharacterKey, showTabCharacterKey];
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
        popup.enabled = [defaults boolForKey:showKeys[n]];
    }
}

// added by Terada( - (IBAction)invisibleCharacterChanged: )
- (IBAction)invisibleCharacterChanged:(id)sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:showTabCharacterKey] forKey:showTabCharacterKey];
	[SUD setBool:[_showTabCharacterButton state] forKey:showTabCharacterKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:showSpaceCharacterKey] forKey:showSpaceCharacterKey];
	[SUD setBool:[_showSpaceCharacterButton state] forKey:showSpaceCharacterKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:showFullwidthSpaceCharacterKey] forKey:showFullwidthSpaceCharacterKey];
	[SUD setBool:[_showFullwidthSpaceCharacterButton state] forKey:showFullwidthSpaceCharacterKey];
	
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:showNewLineCharacterKey] forKey:showNewLineCharacterKey];
	[SUD setBool:[_showNewLineCharacterButton state] forKey:showNewLineCharacterKey];
	
	TSSetInvisibleIndex(SUD, SpaceCharacterKindKey, [_SpaceCharacterKindPopup selectedItem].tag, _undoManager);
	
	TSSetInvisibleIndex(SUD, FullwidthSpaceCharacterKindKey, [_FullwidthSpaceCharacterKindPopup selectedItem].tag, _undoManager);
	
	TSSetInvisibleIndex(SUD, NewLineCharacterKindKey, [_NewLineCharacterKindPopup selectedItem].tag, _undoManager);
	
	TSSetInvisibleIndex(SUD, TabCharacterKindKey, [_TabCharacterKindPopup selectedItem].tag, _undoManager);
	
    [self updateInvisibleCharacterControls:SUD];
	invisibleCharacterTouched = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:@"NeedsForRecolorNotification" object: self];
	
}

// added by Terada( - (IBAction)makeatletterChanged: )
- (IBAction)makeatletterChanged:(id)sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:MakeatletterEnabledKey] forKey:MakeatletterEnabledKey];
	[SUD setBool:[_makeatletterButton state] forKey:MakeatletterEnabledKey];
	
	makeatletterTouched = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:@"NeedsForRecolorNotification" object: self];
}

// Each document reads this when it opens; the Source menu still turns expl3 coloring on and off for one document.
- (IBAction)expl3SyntaxColorPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:expl3SyntaxColoringKey] forKey:expl3SyntaxColoringKey];
	[SUD setBool:(_expl3SyntaxColorButton.state == NSControlStateValueOn) forKey:expl3SyntaxColoringKey];
}

// Autosave is read once at launch, so a change takes effect after TeXShop restarts.
- (IBAction)autoSaveEnabledPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:AutoSaveEnabledKey] forKey:AutoSaveEnabledKey];
	[SUD setBool:(_autoSaveEnabledButton.state == NSControlStateValueOn) forKey:AutoSaveEnabledKey];
	// A backup file is kept only when Versions is off, which follows autosave.
	_keepBackupButton.enabled = ![SUD boolForKey:AutoSaveEnabledKey];
}

- (IBAction)keepBackupPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:KeepBackupKey] forKey:KeepBackupKey];
	[SUD setBool:(_keepBackupButton.state == NSControlStateValueOn) forKey:KeepBackupKey];
}

- (IBAction)saveEncodingMenuPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:EncodingMenuInSaveDialogKey] forKey:EncodingMenuInSaveDialogKey];
	[SUD setBool:(_saveEncodingMenuButton.state == NSControlStateValueOn) forKey:EncodingMenuInSaveDialogKey];
}

// added by Terada( - (IBAction)kpsetoolChanged: )
- (IBAction)kpsetoolChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:KpsetoolKey] forKey:KpsetoolKey];
	
	kpsetoolTouched = YES;
	[SUD setObject:[_kpsetoolField stringValue] forKey:KpsetoolKey];
}

// added by Terada( - (IBAction)bibTeXengineChanged: )
- (IBAction)bibTeXengineChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:BibTeXengineKey] forKey:BibTeXengineKey];
	
	bibTeXengineTouched = YES;
	[SUD setObject:[_bibTeXengineField stringValue] forKey:BibTeXengineKey];
}


/*" Set Command Completion Key"*/
- (IBAction)commandCompletionChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:CommandCompletionCharKey] forKey:CommandCompletionCharKey];
	
	if ([[sender selectedCell] tag] == 0)
		[SUD setObject:@"ESCAPE" forKey:CommandCompletionCharKey];
	else
		[SUD setObject:@"TAB" forKey:CommandCompletionCharKey];
	commandCompletionCharTouched = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:@"CommandCompletionCharNotification" object: self];
	
}



/*" Set Find Panel"*/
- (IBAction)findPanelChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:FindMethodKey] forKey:FindMethodKey];

	if ([[sender selectedCell] tag] == 0)
		[SUD setInteger:0 forKey:FindMethodKey];
	else if ([[sender selectedCell] tag] == 1)
		[SUD setInteger:1 forKey:FindMethodKey];
    else
        [SUD setInteger:2 forKey:FindMethodKey];
}

/*" Set Line Number Size"*/
- (IBAction)lineSizeChanged:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:LineNumberSizeKey] forKey:LineNumberSizeKey];

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
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:LineBreakModeKey] forKey:LineBreakModeKey];
    
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
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:MakeEmptyDocumentKey] forKey:MakeEmptyDocumentKey];

	[SUD setBool:[(NSCell *)sender state] forKey:MakeEmptyDocumentKey];
}

/*" Configure for External Editor "*/
- (IBAction)externalEditorButtonPressed:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:UseExternalEditorKey] forKey:UseExternalEditorKey];

	[SUD setBool:[(NSCell *)sender state] forKey:UseExternalEditorKey];
	 // post a notification so the system will learn about this change
	[[NSNotificationCenter defaultCenter] postNotificationName:ExternalEditorNotification object:self];
	externalEditorTouched = YES;
}


/*" Change Encoding "*/
- (IBAction)encodingChanged:sender
{
	NSString	*oldValue, *value;
	NSStringEncoding	theCode;

	oldValue = [SUD stringForKey:EncodingKey];
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:EncodingKey] forKey:EncodingKey];

	theCode = [[sender selectedCell] tag];
	value = [[TSEncodingSupport sharedInstance] keyForStringEncoding: theCode];
	[SUD setObject:value forKey:EncodingKey];

	// added by mitsu --(G) TSEncodingSupport
	[[NSNotificationCenter defaultCenter] postNotificationName:@"EncodingChangedNotification" object:self];
	encodingTouched = YES;
	NSWindow	*activeWindow = [[TSWindowManager sharedInstance] activeTextWindow];

	if ((activeWindow != nil) && (! [value isEqualToString:oldValue]))
		NSBeginCriticalAlertSheet (nil, nil, nil, nil,
					_prefsWindow, self, nil, NULL, nil,
					NSLocalizedString(@"Currently open files retain their old encoding.", @"Currently open files retain their old encoding."));
// end addition

}

/*" Change Window Opening Behavior "*/
- (IBAction)openAsTabsChanged:sender
{
    NSInteger    oldValue, value;

    oldValue = [SUD integerForKey:OpenAsTabsKey];
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:OpenAsTabsKey] forKey:OpenAsTabsKey];

    value = [[sender selectedCell] tag];
    [SUD setInteger:value forKey:OpenAsTabsKey];
}


- (IBAction)tabIndentPressed:(id)sender
{
    NSInteger        value;
    
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:tabsKey] forKey:tabsKey];
    
    value = [tabIndentField integerValue];
    if (value < 2) {
        value = 2;
//        [tabIndentField setIntegerValue:2];
    } else if (value > 50) {
        value = 50;
//        [tabIndentField setIntegerValue:50];
    }
    [tabIndentField setIntegerValue: value];
    
    [SUD setInteger:value forKey:tabsKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];

}

- (IBAction)firstParagraphIndentPressed:(id)sender
{
    double        value;
    NSInteger     wholeValue;

    
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:SourceFirstLineHeadIndentKey] forKey:SourceFirstLineHeadIndentKey];
    
    value = [firstParagraphIndentField doubleValue];
    // KOCH
    wholeValue = value;
    if (wholeValue < 0)
        wholeValue = 0;
    if (wholeValue > 100)
        wholeValue = 100;
    [firstParagraphIndentField setIntegerValue:wholeValue];
    value = wholeValue;
    /*
    if (value < 0.0) {
        value = 0.0;
        [firstParagraphIndentField setDoubleValue:0];
    } else if (value > 100.0) {
        value = 100.0;
        [firstParagraphIndentField setDoubleValue:100.0];
    }
    */
    
    [SUD setFloat:value forKey:SourceFirstLineHeadIndentKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];
}

- (IBAction)remainingParagraphIndentPressed:(id)sender
{
    double        value;
    NSInteger     wholeValue;
    
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:SourceHeadIndentKey] forKey:SourceHeadIndentKey];
    
    value = [remainingParagraphIndentField doubleValue];
    wholeValue = value;
    if (wholeValue < 0)
        wholeValue = 0;
    if (wholeValue > 100)
        wholeValue = 100;
    [remainingParagraphIndentField setIntegerValue:wholeValue];
    value = wholeValue;
    /*
    if (value < 0.0) {
        value = 0.0;
        [remainingParagraphIndentField setDoubleValue:0.0];
    } else if (value > 100.0) {
        value = 100.0;
        [remainingParagraphIndentField setDoubleValue:100.0];
    }
    */
    
    [SUD setFloat:value forKey:SourceHeadIndentKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];
    
}

- (IBAction)interlineSpacingPressed:(id)sender
{
    double        value;
    NSInteger     wholeValue;
    
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:SourceInterlineSpaceKey] forKey:SourceInterlineSpaceKey];
    
    value = [interlineSpacingField doubleValue];
    wholeValue = value;
    if (wholeValue < 1)
        wholeValue = 1;
    if (wholeValue > 20)
        wholeValue = 20;
    [interlineSpacingField setIntegerValue:wholeValue];
    value = wholeValue;
    /*
    if (value < 1.0) {
        value = 1,0;
        [interlineSpacingField setDoubleValue:1.0];
    } else if (value > 20.0) {
        value = 20.0;
        [interlineSpacingField setDoubleValue:50.0];
    }
    */
    
    [SUD setFloat:value forKey:SourceInterlineSpaceKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontChangedNotification object:self];
}



- (IBAction)useTabPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:TabIndentKey] forKey:TabIndentKey];
    
    [SUD setBool:[(NSButton*)sender state] forKey:TabIndentKey];
}


/*" This method is connected to the 'syntax coloring' checkbox.
"*/
- (IBAction)syntaxColorPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SyntaxColoringEnabledKey] forKey:SyntaxColoringEnabledKey];

    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:SyntaxColoringEnabledKey];
    syntaxColorTouched = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentSyntaxColorNotification object:self];
}



/*" This method is connected to the 'syntax line coloring' checkbox.
"*/
- (IBAction)syntaxColorLinePressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SyntaxColorEntryLineKey] forKey:SyntaxColorEntryLineKey];

     
    [SUD setBool: [(NSCell *)sender state]  forKey:SyntaxColorEntryLineKey];
    syntaxColorLineTouched = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:DocumentSyntaxColorNotification object:self];
}

/*" This method is connected to the 'block cursor' checkbox.
"*/
- (IBAction)blockCursorPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:BlockCursorKey] forKey:BlockCursorKey];

     
    [SUD setBool: [(NSCell *)sender state]  forKey:BlockCursorKey];
}

/*" This method is connected to the 'use font for log and macro editor' checkbox.
"*/
- (IBAction)MacroPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SameFontForMacroKey] forKey:SameFontForMacroKey];

     
    [SUD setBool: [(NSCell *)sender state]  forKey:SameFontForMacroKey];
}


- (IBAction)blockWidthPressed:sender
{
    NSInteger   selectedValue;
    
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:BlockWidthKey] forKey:BlockWidthKey];

    if ([[sender selectedCell] tag] == 0)
        selectedValue = 0;
    else
        selectedValue = 1;
    
    [SUD setInteger: selectedValue forKey:BlockWidthKey];
}


- (IBAction)blockSidePressed:sender
{
    NSInteger   selectedValue;
    
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:BlockSideKey] forKey:BlockSideKey];

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
    NSColor *newColor = [[NSColorPanel sharedColorPanel] color];
    
    [[_undoManager prepareWithInvocationTarget:SUD] setFloat:[SUD floatForKey:BlockCursorRKey] forKey:BlockCursorRKey];
    [[_undoManager prepareWithInvocationTarget:SUD] setFloat:[SUD floatForKey:BlockCursorGKey] forKey:BlockCursorGKey];
    [[_undoManager prepareWithInvocationTarget:SUD] setFloat:[SUD floatForKey:BlockCursorBKey] forKey:BlockCursorBKey];
    
    [SUD setFloat: [newColor redComponent] forKey:BlockCursorRKey];
    [SUD setFloat: [newColor greenComponent] forKey:BlockCursorGKey];
    [SUD setFloat: [newColor blueComponent] forKey: BlockCursorBKey];
}



/*" This method is connected to the "Source Window Position" Matrix.
 
 This method will be called when the matrix changes. Target 0 means 'all windows start at a fixed position', target 1 means 'remember window position'.
 "*/
- (IBAction)consoleWindowPosChanged:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:ConsoleWindowPosModeKey] forKey:ConsoleWindowPosModeKey];
    
    [SUD setInteger:[[sender selectedCell] tag] forKey:ConsoleWindowPosModeKey];
    [_consoleWindowPosMatrix selectCellWithTag:[[sender selectedCell] tag]];
    
    if ([[sender selectedCell] tag] == 0)
       [_consoleWindowPosButton setEnabled: YES];
    else
         [_consoleWindowPosButton setEnabled: NO];
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
        [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:ConsoleWindowFixedPosKey] forKey:ConsoleWindowFixedPosKey];
        [SUD setObject:[activeConsole stringWithSavedFrame] forKey:ConsoleWindowFixedPosKey];
        
        // just in case: the radio button must be checked as well.
        /* koch: the code below is harmless but probably unnecessary since the button can only
         be pressed if the radio button is in the fixed position mode */
        [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:ConsoleWindowPosModeKey] forKey:ConsoleWindowPosModeKey];
        [SUD setInteger:ConsoleWindowPosFixed forKey:ConsoleWindowPosModeKey];
        [_consoleWindowPosMatrix selectCellWithTag:ConsoleWindowPosFixed];
    }
}


- (IBAction)XMLChapterButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLChapterTagKey] forKey:XMLChapterTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLChapterTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSectionButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLSectionTagKey] forKey:XMLSectionTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSubsectionButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLSubsectionTagKey] forKey:XMLSubsectionTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSubsectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLSubsubsectionButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLSubsubsectionTagKey] forKey:XMLSubsubsectionTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLSubsubsectionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLIntroductionButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLIntroductionTagKey] forKey:XMLIntroductionTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLIntroductionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLConclusionButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLConclusionTagKey] forKey:XMLConclusionTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLConclusionTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLExercisesButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLExercisesTagKey] forKey:XMLExercisesTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLExercisesTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLProjectButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLProjectTagKey] forKey:XMLProjectTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLProjectTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLFigureButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLFigureTagKey] forKey:XMLFigureTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLFigureTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLTableButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLTableTagKey] forKey:XMLTableTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLTableTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}

- (IBAction)XMLMarkButtonChanged:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:XMLMarkTagKey] forKey:XMLMarkTagKey];
    [SUD setBool:[(NSButton *)sender state] forKey:XMLMarkTagKey];
    [(TSAppDelegate *)NSApp.delegate updateXMLTabs];
}










/*" This method is connected to the 'select on activate' checkbox.
"*/
- (IBAction)selectActivatePressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:AcceptFirstMouseKey] forKey:AcceptFirstMouseKey];

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AcceptFirstMouseKey];
}


/*" This method is connected to the 'parens matching' checkbox.
"*/
- (IBAction)parensMatchPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:ParensMatchingEnabledKey] forKey:ParensMatchingEnabledKey];

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:ParensMatchingEnabledKey];
}

/*" This method is connected to the 'spell checking' checkbox.
"*/
- (IBAction)spellCheckPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SpellCheckEnabledKey] forKey:SpellCheckEnabledKey];

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:SpellCheckEnabledKey];
}

- (IBAction)editorAddBracketsPressed:(id)sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:EditorCanAddBracketsKey] forKey:EditorCanAddBracketsKey];
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:EditorCanAddBracketsKey];
    editorCanAddBrackets = [SUD boolForKey:EditorCanAddBracketsKey];
}

- (IBAction)spellCorrectPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:AutomaticSpellingCorrectionEnabledKey] forKey:AutomaticSpellingCorrectionEnabledKey];
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AutomaticSpellingCorrectionEnabledKey];
}


/*" This method is connected to the 'line number' checkbox.
"*/
- (IBAction)lineNumberButtonPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:LineNumberEnabledKey] forKey:LineNumberEnabledKey];

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:LineNumberEnabledKey];
}

/*" This method is connected to the 'tags menu' checkbox.
 "*/
- (IBAction)tagMenuButtonPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:TagMenuInMenuBarKey] forKey:TagMenuInMenuBarKey];
    
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:TagMenuInMenuBarKey];
     [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] setHidden:( ![SUD boolForKey:TagMenuInMenuBarKey])];
}


// added by Terada (-(IBAction)showInvisibleCharacterButtonPressed:)
- (IBAction)showInvisibleCharacterButtonPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:ShowInvisibleCharactersEnabledKey] forKey:ShowInvisibleCharactersEnabledKey];
	
	[SUD setBool:[(NSCell *)sender state] forKey:ShowInvisibleCharactersEnabledKey];
}

/*" This method is connected to the 'Arabic, Persian, Hebrew' checkbox.
 "*/
- (IBAction)midEastButtonPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:RightJustifyKey] forKey:RightJustifyKey];
	
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:RightJustifyKey];
}





/*" This method is connected to the 'shell escape warning' checkbox.
"*/
- (IBAction)escapeWarningChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:WarnForShellEscapeKey] forKey:WarnForShellEscapeKey];

	[SUD setBool:[(NSCell *)sender state] forKey:WarnForShellEscapeKey];
}


/*" This method is connected to the 'auto complete' checkbox.
"*/
- (IBAction)autoCompletePressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:AutoCompleteEnabledKey] forKey:AutoCompleteEnabledKey];

	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:AutoCompleteEnabledKey];
	autoCompleteTouched = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:DocumentAutoCompleteNotification object:self];

}

/*" This method is connected to the 'BibDesk Complete' checkbox.
"*/
- (IBAction)bibDeskCompletePressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:BibDeskCompletionKey] forKey:BibDeskCompletionKey];
	
	[SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:BibDeskCompletionKey];
	bibDeskCompleteTouched = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:DocumentBibDeskCompleteNotification object:self];

}





//==============================================================================
// Preview pane
//==============================================================================
/*" This method is connected to the "PDF Window Position" Matrix.

A tag of 0 means don't save the window position, a tag of 1 to save the setting. This should only flag the request to save the position, the actual saving of position and size can be left to [NSWindow setAutoSaveFrameName].
"*/
- (IBAction)pdfWindowPosChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:PdfWindowPosModeKey] forKey:PdfWindowPosModeKey];

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfWindowPosModeKey];

	/* koch: button enabled only if appropriate */
	if ([[sender selectedCell] tag] == 0)
		[_pdfWindowPosButton setEnabled: YES];
	else
		[_pdfWindowPosButton setEnabled: NO];
}

//==============================================================================
/*" This method is connected to the "HTML Window Position" Matrix.

A tag of 0 means don't save the window position, a tag of 1 to save the setting. This should only flag the request to save the position, the actual saving of position and size can be left to [NSWindow setAutoSaveFrameName].
"*/
- (IBAction)htmlWindowPosChanged:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:HtmlWindowPosModeKey] forKey:HtmlWindowPosModeKey];

    [SUD setInteger:[[sender selectedCell] tag] forKey:HtmlWindowPosModeKey];

    /* koch: button enabled only if appropriate */
    if ([[sender selectedCell] tag] == 0)
        [_htmlWindowPosButton setEnabled: YES];
    else
        [_htmlWindowPosButton setEnabled: NO];
}

/*" This method is connected to the 'use current pos as default' button.
"*/
- (IBAction)currentPdfWindowPosDefault:sender
{
	NSWindow	*activeWindow;

	activeWindow = [[TSWindowManager sharedInstance] activePDFWindow];

	if (activeWindow != nil) {
		[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:PdfWindowFixedPosKey] forKey:PdfWindowFixedPosKey];
		[SUD setObject:[activeWindow stringWithSavedFrame] forKey:PdfWindowFixedPosKey];

		// just in case: the radio button must be checked as well.
		[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:PdfWindowPosModeKey] forKey:PdfWindowPosModeKey];
		[SUD setInteger:DocumentWindowPosFixed forKey:PdfWindowPosModeKey];
		[_sourceWindowPosMatrix selectCellWithTag:PdfWindowPosFixed];
	}
}

/*" This method is connected to the 'use current pos as default' button.
"*/
- (IBAction)currentHtmlWindowPosDefault:sender
{
    NSWindow    *activeWindow;

    activeWindow = [[TSWindowManager sharedInstance] activeHTMLWindow];

    if (activeWindow != nil) {
        [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:HtmlWindowFixedPosKey] forKey:HtmlWindowFixedPosKey];
        [SUD setObject:[activeWindow stringWithSavedFrame] forKey:HtmlWindowFixedPosKey];

        // just in case: the radio button must be checked as well.
        // [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:HtmlWindowPosModeKey] forKey:HtmlWindowPosModeKey];
       //  [SUD setInteger:HtmlWindowPosFixed forKey:HtmlWindowPosModeKey];
       //  [_sourceWindowPosMatrix selectCellWithTag:HtmlWindowPosFixed];
    }
}


/*" This method is connected to the magnification text field on the Preview pane'.
"*/
- (IBAction)magChanged:sender
{
	// NSRunAlertPanel(@"warning", @"not yet implemented", nil, nil, nil);

	// TSPreviewWindow	*activeWindow;
	double	mag, magnification;


	// The comment below fixes a bug; magnification didn't take if no pdf window open
    // activeWindow = (TSPreviewWindow *)[[TSWindowManager sharedInstance] activePDFWindow];
	//   if (activeWindow != nil)

	{
		[[_undoManager prepareWithInvocationTarget:SUD] setFloat:[SUD floatForKey:PdfMagnificationKey] 				forKey:PdfMagnificationKey];
		mag = [_magTextField doubleValue];
		if (mag < 20.0) {
			mag = 20;
			[_magTextField setDoubleValue:mag];
			[_magTextField display];
		}
		else if (mag > 400.0) {
			mag = 400;
			[_magTextField setDoubleValue:mag];
			[_magTextField display];
		}
		magnification = mag / 100.0;
		[SUD setFloat:magnification forKey:PdfMagnificationKey];
		magnificationTouched = YES;
		// post a notification so all open documents can change their magnification
		[[NSNotificationCenter defaultCenter] postNotificationName:MagnificationChangedNotification object:self];

	}

}



/*" This method is connected to the 'scroll' checkbox.
"*/
- (IBAction)scrollPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:NoScrollEnabledKey] forKey:NoScrollEnabledKey];

	[SUD setBool:[(NSCell *)sender state] forKey:NoScrollEnabledKey];
}

- (IBAction)autoPDFChanged:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:PdfRefreshKey] forKey:PdfRefreshKey];
	[SUD setBool:[(NSCell *)sender state] forKey:PdfRefreshKey];
}

- (IBAction)antialiasChanged:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:AntiAliasKey] forKey:AntiAliasKey];
	[SUD setBool:[(NSCell *)sender state] forKey:AntiAliasKey];
}

- (IBAction)sourceAndPreviewInSameWindowChanged:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SourceAndPreviewInSameWindowKey] forKey:SourceAndPreviewInSameWindowKey];
    NSInteger myTag = [sender tag];
    BOOL result;
    if (myTag == 0)
        result = NO;
    else
        result = YES;
	[SUD setBool:result forKey:SourceAndPreviewInSameWindowKey];
}

- (IBAction)sourceOnLeftChanged:sender
{
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SwitchSidesKey] forKey:SwitchSidesKey];
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
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:PdfPageStyleKey] forKey:PdfPageStyleKey];

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfPageStyleKey];
}

/*" This method is connect to the 'first double page' radio buttons.
"*/
- (IBAction)displayAsBookChanged:(NSButton *)sender
{
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:DisplayAsBookKey] forKey:DisplayAsBookKey];
    [SUD setBool:sender.state == NSControlStateValueOn forKey:DisplayAsBookKey];
}

- (IBAction)firstDoublePageChanged:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:PdfFirstPageStyleKey] forKey:PdfFirstPageStyleKey];

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
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:PdfKitFitSizeKey] forKey:PdfKitFitSizeKey];

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfKitFitSizeKey];
}


/*" This method is connected to image copy type popup button. "*/
- (IBAction)imageCopyTypeChanged:sender
{
	// mitsu 1.29b
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD
integerForKey:PdfCopyTypeKey] forKey:PdfCopyTypeKey];
	// uncheck menu item Preview=>Copy Format
	NSMenu *previewMenu = [[[NSApp mainMenu] itemWithTitle:
						NSLocalizedString(@"Preview", @"Preview")] submenu];

	NSMenu *formatMenu = [[previewMenu itemWithTitle:
						NSLocalizedString(@"Copy Format", @"Copy Format")] submenu];
	id item = [formatMenu itemWithTag: [SUD integerForKey:PdfCopyTypeKey]];
	if (item)
		[[_undoManager prepareWithInvocationTarget:[NSApp delegate]] changeImageCopyType: item];

	item = [formatMenu itemWithTag: [[sender selectedCell] tag]];
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
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:PdfKitMouseModeKey] forKey:PdfKitMouseModeKey];

	[SUD setInteger:[[sender selectedCell] tag] forKey:PdfKitMouseModeKey];
}

/*" This method is connected to default mouse mode popup button. "*/
- (IBAction)colorMapChanged:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD integerForKey:PdfColorMapKey] forKey:PdfColorMapKey];

	[SUD setBool:([(NSCell *)sender state]==NSOnState) forKey:PdfColorMapKey];
}

- (IBAction)colorParam1Changed:sender
{
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:PdfColorParam1Key] forKey:PdfColorParam1Key];

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
    [_prefsWindow makeFirstResponder:_prefsWindow];
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
            // If Settings opened during the initial search, use its sheet and undo group.
            BOOL applyInitial = initial && !self->_prefsWindow.visible;
            if ((!initial && !self->_prefsWindow.visible) || ![self enginePathSnapshotMatches:snapshot initial:applyInitial]) return;
            NSAlert *alert = [NSAlert new];
            alert.messageText = NSLocalizedString(initial ? @"Set Up TeX Engine Paths" : @"Detected Engine Paths", @"");
            BOOL hasPaths = [found[@"TeX"] count] || [found[@"Ghostscript"] count];
            alert.informativeText = NSLocalizedString(@"The newest detected installation is selected. You can choose another candidate below. Custom engine commands and the alternate path are unchanged.", @"");
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
                    NSTextField *missing = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Not found (current setting will be kept)", @"")];
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
            if (![found[@"TeX"] count]) alert.informativeText = [alert.informativeText stringByAppendingFormat:@"\n\n%@", NSLocalizedString(@"Install a TeX distribution, then run Auto Setup in Settings > Engine.", @"")];
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
                    if (!applyInitial) [[self->_undoManager prepareWithInvocationTarget:SUD] setObject:snapshot[i] forKey:keys[i]];
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
- (IBAction)tetexBinPathChanged:sender
{
    NSString *newValue;
    
	// register the undo messages first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:TetexBinPath] 				forKey:TetexBinPath];

    newValue = [[_tetexBinPathField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[SUD setObject: newValue forKey:TetexBinPath];
}

//==============================================================================
/*" This method is connected to the textField that holds the HtmlHome value
"*/
- (IBAction)HtmlHomeChanged:sender
{
    NSString *newValue;
    
    // register the undo messages first
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:HtmlHomeKey]                 forKey:HtmlHomeKey];

    newValue = [[_HtmlHomeField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [SUD setObject: newValue forKey:HtmlHomeKey];
}


//==============================================================================
/*" This method is connected to the textField that holds the alternate path.
"*/
- (IBAction)altPathChanged:sender
{
    NSString *newValue;
    
    // register the undo messages first
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:AltPathKey] forKey:AltPathKey];

    newValue = [[_altPathField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [SUD setObject: newValue forKey:AltPathKey];
}


//==============================================================================
/*" This method is connected to the textField that holds the gs bin path.
"*/
- (IBAction)gsBinPathChanged:sender
{
     NSString *newValue;
    
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:GSBinPath] 				forKey:GSBinPath];
    
    newValue = [[_gsBinPathField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];

	[SUD setObject: newValue forKey:GSBinPath];
}

//==============================================================================
// TeX pane
//==============================================================================
/*" This method is connected to the textField that holds the TeX command. It is located on the TeX pane.
"*/
- (IBAction)texProgramChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:TexCommandKey] forKey:TexCommandKey];

	[SUD setObject:[_texCommandTextField stringValue] forKey:TexCommandKey];
}

/*" This method is connected to the textField that holds the LaTeX command. It is located on the TeX pane.
"*/
- (IBAction)latexProgramChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:LatexCommandKey] forKey:LatexCommandKey];

	[SUD setObject:[_latexCommandTextField stringValue] forKey:LatexCommandKey];
}

/*" This method is connected to the textField that holds the tex + ghostscript command. It is located on the TeX pane.
"*/
- (IBAction)texGSProgramChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:TexGSCommandKey] forKey:TexGSCommandKey];

	[SUD setObject:[_texGSCommandTextField stringValue] forKey:TexGSCommandKey];
}

/*" This method is connected to the textField that holds the latextex + ghostscript command. It is located on the TeX pane.
"*/
- (IBAction)latexGSProgramChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:LatexGSCommandKey] forKey:LatexGSCommandKey];

	[SUD setObject:[_latexGSCommandTextField stringValue] forKey:LatexGSCommandKey];
}

/*" This method is connected to the 'save postscript' checkbox.
"*/
- (IBAction)savePSPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SavePSEnabledKey] forKey:SavePSEnabledKey];

	[SUD setBool:[(NSCell *)sender state] forKey:SavePSEnabledKey];
}

#ifdef USESPARKLE

/*" Sparkle Actions 
"*/
- (IBAction)sparkleAutomaticCheck:sender
{
    sparkleTouched = YES;

    
    BOOL theValue = [(NSCell *) sender state];
    
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:SparkleAutomaticUpdateKey] forKey:SparkleAutomaticUpdateKey];
    [_sparkleIntervalMatrix setEnabled: theValue];
    [SUD setBool:theValue forKey:SparkleAutomaticUpdateKey];
    
    
    [[TSSparkleController sharedUpdater] setAutomaticallyChecksForUpdates: theValue ];
    
}

- (IBAction)sparkleInterval:sender
{
    sparkleTouched = YES;

    
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:SparkleIntervalKey] forKey:SparkleIntervalKey];
    
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
- (IBAction)texScriptProgramChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:TexScriptCommandKey] forKey:TexScriptCommandKey];

	[SUD setObject:[_texScriptCommandTextField stringValue] forKey:TexScriptCommandKey];
}

/*" This method is connected to the textField that holds the latex script command. It is located on the TeX pane.
"*/
- (IBAction)latexScriptProgramChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:LatexScriptCommandKey] forKey:LatexScriptCommandKey];

	[SUD setObject:[_latexScriptCommandTextField stringValue] forKey:LatexScriptCommandKey];
}

/*" This method is connected to the textField that holds the alternate engine command. It is located on the Misc pane.
"*/
- (IBAction)alternateEngineChanged:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD objectForKey:AlternateEngineKey] forKey:AlternateEngineKey];

    [SUD setObject:[_alternateEngineTextField stringValue] forKey:AlternateEngineKey];
}


/*" This method is connected to the "Default Program" matrix on the TeX pane.

A tag of 0 means use TeX, a tag of 1 means use LaTeX.
"*/
- (IBAction)defaultProgramChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:DefaultCommandKey] forKey:DefaultCommandKey];

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:DefaultCommandKey];
	if ([[sender selectedCell] tag] == 2) {
		[_engineTextField setEnabled: YES];
		[_engineTextField setEditable: YES];
		[_engineTextField setSelectable: YES];
		[_engineTextField selectText:self];
	}
	else
		[_engineTextField setEnabled: NO];
}

- (IBAction)setEngine:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setObject:[SUD stringForKey:DefaultEngineKey] forKey:DefaultEngineKey];

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setObject:[sender stringValue] forKey:DefaultEngineKey];
}

/*" This method is connected to the "Default Script" matrix on the TeX pane.

A tag of 100 means use pdftex, a tag of 101 means use tex + ghostscript, a tag of 102 means use
person script. See also: DefaultTypesetMode.

"*/
- (IBAction)defaultScriptChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD boolForKey:DefaultScriptKey] forKey:DefaultScriptKey];

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:DefaultScriptKey];
}

- (IBAction)syncChanged: sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:SyncMethodKey] forKey:SyncMethodKey];

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:SyncMethodKey];
}

/* // comment out by Terada
- (IBAction)defaultBibtexChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:BibtexCommandKey] forKey:BibtexCommandKey];

	[SUD setInteger:[[sender selectedCell] tag] forKey:BibtexCommandKey];
}
*/

- (IBAction)distillerChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD integerForKey:DistillerCommandKey] forKey:DistillerCommandKey];

	[SUD setInteger:[[sender selectedCell] tag] forKey:DistillerCommandKey];
}

// zenitani 1.35 (C)
- (IBAction)ptexUtfOutputPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:ptexUtfOutputEnabledKey] forKey:ptexUtfOutputEnabledKey];

	[SUD setBool:[(NSCell *)sender state] forKey:ptexUtfOutputEnabledKey];

	// zenitani 2.10 (A) UTF-8 + utf.sty situation
	[[TSEncodingSupport sharedInstance] setupForEncoding];
}

// koch, 4/10/2011
- (IBAction)convertUTFPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:AutomaticUTF8MACtoUTF8ConversionKey] forKey:AutomaticUTF8MACtoUTF8ConversionKey];
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
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:AutoOpenRootFileKey] forKey:AutoOpenRootFileKey];
    
    [SUD setBool:[(NSButton *)sender state] forKey:AutoOpenRootFileKey];
}

- (IBAction)miniaturizeRootFilePressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:MiniaturizeRootFileKey] forKey:MiniaturizeRootFileKey];
    
    [SUD setBool:[(NSButton *)sender state] forKey:MiniaturizeRootFileKey];
}

- (void)updateSpellingControlsFromDefaults:(NSUserDefaults *)defaults
{
    BOOL enabled = [defaults boolForKey:@"TeXAwareSpellChecking"];
    _texAwareSpellCheckButton.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    // The exclusion rules apply only to TeX-aware spell checking.
    _editSpellingExclusionsButton.enabled = enabled;
    _spellCheckCommands.enabled = !enabled;
    _spellCheckParameters.enabled = !enabled;
    _spellCheckComments.enabled = !enabled;
}

- (IBAction)texAwareSpellCheckPressed:(NSButton *)sender
{
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:@"TeXAwareSpellChecking"]
                                                   forKey:@"TeXAwareSpellChecking"];
    [SUD setBool:(sender.state == NSControlStateValueOn) forKey:@"TeXAwareSpellChecking"];
    [self updateSpellingControlsFromDefaults:SUD];
    [TSSpellSupport preferencesDidChange];
}

- (IBAction)editSpellingExclusions:(id)sender
{
    [TSSpellSupport editSpellingExclusions:sender];
}

- (IBAction)spellCheckCommandPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:TurnOffCommandSpellCheckKey] forKey:TurnOffCommandSpellCheckKey];
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state] forKey:TurnOffCommandSpellCheckKey];
}

- (IBAction)spellCheckParameterPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:TurnOffParameterSpellCheckKey] forKey:TurnOffParameterSpellCheckKey];
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state]  forKey:TurnOffParameterSpellCheckKey];
    
}

- (IBAction)spellCheckCommentPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setBool:[SUD boolForKey:TurnOffCommentSpellCheckKey] forKey:TurnOffCommentSpellCheckKey];
    
    [SUD setBool:[(NSCell *)[sender selectedCell] state]  forKey:TurnOffCommentSpellCheckKey];
}




/*" This method is connected to the "Console" matrix on the TeX pane.

A tag of 0 means "always", a tag of 1 means "when errors occur".
"*/
- (IBAction)consoleBehaviorChanged:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD boolForKey:ConsoleBehaviorKey] forKey:ConsoleBehaviorKey];

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setInteger:[[sender selectedCell] tag] forKey:ConsoleBehaviorKey];
}

- (IBAction)dictionaryPressed: sender
{
    
    NSString *language = [[sender selectedItem] title];
    
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger: [SUD integerForKey: spellingAutomaticDefaultKey] forKey: spellingAutomaticDefaultKey];
    
    [[_undoManager prepareWithInvocationTarget:SUD] setObject: [SUD objectForKey: spellingLanguageDefaultKey] forKey: spellingLanguageDefaultKey];
    
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
	BOOL	oldBoolValue, newBoolValue;
    NSInteger oldValue, newValue;
	NSInteger		tagValue;
	
	oldBoolValue = [SUD boolForKey:BringPdfFrontOnTypesetKey];
    oldValue = [SUD integerForKey:BringFrontOnTypesetKey];
	tagValue = [[sender selectedCell] tag];
    
    if (tagValue == 1)
		newBoolValue = NO;
	else
		newBoolValue = YES;
    
    newValue = tagValue;
    if (newValue > 2)
        newValue = 0;
    
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setBool:oldBoolValue forKey:BringPdfFrontOnTypesetKey];
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:oldValue forKey:BringFrontOnTypesetKey];
    
	[SUD setBool:newBoolValue forKey:BringPdfFrontOnTypesetKey];
    [SUD setInteger:newValue forKey: BringFrontOnTypesetKey];
    
}

/*" This method is connected to the "Console" matrix on the TeX pane.

A tag of 0 means "always", a tag of 1 means "when errors occur".
"*/
- (IBAction)saveRelatedButtonPressed:sender
{
	// register the undo message first
	[[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD boolForKey:SaveRelatedKey] forKey:SaveRelatedKey];

	// since the default program values map identically to the tags of the NSButtonCells,
	// we can use the tag directly here.
	[SUD setBool:[(NSCell *)sender state] forKey:SaveRelatedKey];
}

- (IBAction)useTransparencyPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD boolForKey:UseTransparencyKey] forKey:UseTransparencyKey];

    // since the default program values map identically to the tags of the NSButtonCells,
    // we can use the tag directly here.
    [SUD setBool:[(NSCell *)sender state] forKey:UseTransparencyKey];
}

/*" On Typesetting Pane

A tag of 0 means "no", a tag of 1 means "yes".
"*/
- (IBAction)syncTabButtonPressed:sender
{
    // register the undo message first
    [[_undoManager prepareWithInvocationTarget:SUD] setInteger:[SUD boolForKey:SyncUseTabsKey] forKey:SyncUseTabsKey];

    // since the default program values map identically to the tags of the NSButtonCells,
    // we can use the tag directly here.
    [SUD setBool:[(NSCell *)sender state] forKey:SyncUseTabsKey];
}


//==============================================================================
// other target/action methods
//==============================================================================
/*" This method is connected to the OK button.
"*/
- (IBAction)okButtonPressed:sender
{
    [self cancelEnginePathDiscovery];
    [[TSDockIconController sharedController] acceptEditing];
	// save everything to the user defaults

    [self okForColor];
    
 /* WARNING: the next seven commands were added by koch on March 17.
		They are needed because the TextBox fields do not send a command
		until the return key is pressed. But pressing the return key also
		closes preferences. Users will instead modify the text and then
		click elsewhere to modify other preferences, only to discover that
		these preferences weren't changed. A user sent email asking how to
		activate pdfelatex in the old TeXShop, so I tried it on
		the new program and couldn't! */
// See mitsu change below instead
//        [self tabsChanged: self];
//        [self texProgramChanged: self];
//        [self latexProgramChanged: self];
//        [self texGSProgramChanged: self];
//        [self latexGSProgramChanged: self];
//        [self texScriptProgramChanged: self];
//        [self latexScriptProgramChanged: self];

// added by mitsu --(M) Path Settings on "okButtonPressed:" in TSPreferences
// This is a simpler way to reflect changes in the controls
	[_prefsWindow makeFirstResponder: _prefsWindow];
// end addition

	[SUD synchronize];

    [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] setHidden:( ![SUD boolForKey:TagMenuInMenuBarKey])];

    editorCanAddBrackets = [SUD boolForKey: EditorCanAddBracketsKey];
    
    
 	// close the window
	// [_prefsWindow performClose:self];
    [_prefsWindow close];
}

/*" This method is connected to the Cancel button.
"*/
- (IBAction)cancelButtonPressed:sender
{
    [self cancelEnginePathDiscovery];
    BOOL oldTeXAwareSpelling = [SUD boolForKey:@"TeXAwareSpellChecking"];
    [self cancelForColor];
    // undo everyting
	[_undoManager endUndoGrouping];
	[_undoManager undo];
    if (oldTeXAwareSpelling != [SUD boolForKey:@"TeXAwareSpellChecking"])
        [TSSpellSupport preferencesDidChange];
    [[TSDockIconController sharedController] cancelEditing];

     [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] setHidden:( ![SUD boolForKey:TagMenuInMenuBarKey])];
	// close the window
	// [_prefsWindow performClose:self];
    [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Tags", @"Tags")] setHidden:( ![SUD boolForKey:TagMenuInMenuBarKey])];
     [_prefsWindow close];
	
//	[PreviewBackgroundColor release];
	PreviewBackgroundColor = [NSColor colorWithCalibratedRed: [SUD floatForKey:PdfPageBack_RKey]
													   green: [SUD floatForKey:PdfPageBack_GKey] blue: [SUD floatForKey:PdfPageBack_BKey]
													   alpha: 1];
//	[PreviewBackgroundColor retain];
	
	/* koch: undo font changes */
	if (externalEditorTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:ExternalEditorNotification object:self];
	if (fontTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:DocumentFontRevertNotification object:self];
	if (consoleFontTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:ConsoleFontChangedNotification object:self];
	if (consoleBackgroundColorTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:ConsoleBackgroundColorChangedNotification object:self];
	if (consoleForegroundColorTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:ConsoleForegroundColorChangedNotification object:self];
	if (sourceBackgroundColorTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:SourceBackgroundColorChangedNotification object:self];
    if (sourceTextColorTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:SourceTextColorChangedNotification object:self];
	if (previewBackgroundColorTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:PreviewBackgroundColorChangedNotification object:self];
	if (magnificationTouched)
		[[NSNotificationCenter defaultCenter] postNotificationName:MagnificationRevertNotification object:self];
	
	/* below we must reset a preference because it will not be undone in time */
	if (syntaxColorTouched) {
		[SUD setBool:oldSyntaxColor forKey:SyntaxColoringEnabledKey];
		[[NSNotificationCenter defaultCenter] postNotificationName:DocumentSyntaxColorNotification object:self];
	}
    if (syntaxColorLineTouched) {
        [SUD setBool:oldSyntaxLineColor forKey:SyntaxColorEntryLineKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:DocumentSyntaxColorNotification object:self];
    }
	if (autoCompleteTouched) {
		[SUD setBool:oldAutoComplete forKey:AutoCompleteEnabledKey];
		[[NSNotificationCenter defaultCenter] postNotificationName:DocumentAutoCompleteNotification object:self];
	}
	if (bibDeskCompleteTouched) {
		[SUD setBool:oldBibDeskComplete forKey:BibDeskCompletionKey];
		[[NSNotificationCenter defaultCenter] postNotificationName:DocumentBibDeskCompleteNotification object:self];
	}
    
#ifdef USESPARKLE
    if (sparkleTouched) {
        [[TSSparkleController sharedUpdater] setAutomaticallyChecksForUpdates: oldSparkleAutomaticUpdate];
        
        [[TSSparkleController sharedUpdater] setUpdateCheckInterval:oldSparkleInterval];
    }
#endif
   
    
	// added by mitsu --(G) TSEncodingSupport
	if (encodingTouched) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"EncodingChangedNotification" object: self ];
	}
	if (commandCompletionCharTouched) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"CommandCompletionCharNotification" object: self];
	}
	// added by Terada
	if (highlightTouched || invisibleCharacterTouched || makeatletterTouched) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"NeedsForRecolorNotification" object: self];
	}
    
    [self cancelForColor];
    
	// end addition

	// The user defaults have changed. Force update of the user interface.
	/* koch: The code below doesn't take because the undo manager doesn't actually
		undo here. It calls undo during the next event loop. So the code below is called too soon.
		I called it again when the preference panel is shown. */
	//    [self updateControlsFromUserDefaults:SUD];
    [self refreshRuntimePreferences];
}

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
	fileName = [[NSBundle mainBundle] pathForResource:@"FactoryDefaults" ofType:@"plist"];
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

//==============================================================================
// helpers
//==============================================================================

/*"  %{This method is not to be called from outside of this class.}

This method retrieves the application preferences from the defaults object and sets the controls in the window accordingly.
"*/
- (void)updateControlsFromUserDefaults:(NSUserDefaults *)defaults
{
	NSData	*fontData, *attributesData;
	double	magnification;
	NSInteger		mag, tabSize;
	NSInteger		myTag, myInteger;
	BOOL	myBool;
	NSNumber    *myNumber;
    
    fontData = [defaults objectForKey:DocumentFontKey];
	if (fontData != nil)
	{
		self.documentFont = [NSUnarchiver unarchiveObjectWithData:fontData];
	}
    
    attributesData = [defaults objectForKey:DocumentFontAttributesKey];
    if (attributesData != nil)
    {
        self.fontAttributes = [NSUnarchiver unarchiveObjectWithData:attributesData];
    }
    
    
	[self updateDocumentFontTextField];
	[self updateConsoleFontTextField];

	[_sourceWindowPosMatrix selectCellWithTag:[defaults integerForKey:DocumentWindowPosModeKey]];
	/* koch: */
	if ([defaults integerForKey:DocumentWindowPosModeKey] == 0)
		[_docWindowPosButton setEnabled: YES];
	else
		[_docWindowPosButton setEnabled: NO];
    [_tabIndentButton setState:[defaults boolForKey:TabIndentKey]];
	[_syntaxColorLineButton setState:[defaults boolForKey:SyntaxColorEntryLineKey]];
    [_syntaxColorButton setState:[defaults boolForKey:SyntaxColoringEnabledKey]];
	[_selectActivateButton setState:[defaults boolForKey:AcceptFirstMouseKey]];
	[_parensMatchButton setState:[defaults boolForKey:ParensMatchingEnabledKey]];
	[_escapeWarningButton setState:[defaults boolForKey:WarnForShellEscapeKey]];
	[_spellCheckButton setState:[defaults boolForKey:SpellCheckEnabledKey]];
    [_editorAddBracketsButton setState:[defaults boolForKey:EditorCanAddBracketsKey]];
    [_autoSpellCorrectButton setState:[defaults boolForKey:AutomaticSpellingCorrectionEnabledKey]];
	[_lineNumberButton setState:[defaults boolForKey:LineNumberEnabledKey]];
    [_tagMenuButton setState:[defaults boolForKey:TagMenuInMenuBarKey]];
	[_showInvisibleCharactersButton setState:[defaults boolForKey:ShowInvisibleCharactersEnabledKey]];
	[_midEastButton setState:[defaults boolForKey:RightJustifyKey]];
	[_autoCompleteButton setState:[defaults boolForKey:AutoCompleteEnabledKey]];
	[_bibDeskCompleteButton setState:[defaults boolForKey:BibDeskCompletionKey]];
	[_autoPDFButton setState:[defaults boolForKey:PdfRefreshKey]];
    [_antialiasButton setState:[defaults boolForKey:AntiAliasKey]];
	[_openEmptyButton setState:[defaults boolForKey:MakeEmptyDocumentKey]];
	[_externalEditorButton setState:[defaults boolForKey:UseExternalEditorKey]];
	[_ptexUtfOutputButton setState:[defaults boolForKey:ptexUtfOutputEnabledKey]]; // zenitani 1.35 (C)
	[_convertUTFButton setState:[defaults boolForKey:AutomaticUTF8MACtoUTF8ConversionKey]];
    [_openRootFileButton  setState:[defaults boolForKey:AutoOpenRootFileKey]];
    [_miniaturizeRootFileButton setState:[defaults boolForKey:MiniaturizeRootFileKey]];
    [_sparkleAutomaticButton setState: [defaults boolForKey: SparkleAutomaticUpdateKey]];
    [_sparkleIntervalMatrix setEnabled: [defaults boolForKey: SparkleAutomaticUpdateKey]];
    [_sparkleIntervalMatrix selectCellWithTag: [defaults integerForKey: SparkleIntervalKey]];
#ifdef USESPARKLE
    // Added by Terada: reflect Sparkle's actual settings, including its consent dialog.
    if (defaults == SUD && [TSSparkleController sharedUpdater] != nil) {
        SPUUpdater *updater = [TSSparkleController sharedUpdater];
        [_sparkleAutomaticButton setState:updater.automaticallyChecksForUpdates];
        [_sparkleIntervalMatrix setEnabled:updater.automaticallyChecksForUpdates];
        NSTimeInterval interval = updater.updateCheckInterval;
        [_sparkleIntervalMatrix selectCellWithTag:(interval < 604800 ? 1 : (interval < 2629800 ? 2 : 3))];
    }
#endif
    [_consoleMatrix selectCellWithTag: [defaults integerForKey: ConsoleBehaviorKey]];
    [_spellCheckCommands setState:[defaults boolForKey:TurnOffCommandSpellCheckKey]];
    [_spellCheckParameters setState:[defaults boolForKey:TurnOffParameterSpellCheckKey]];
    [_spellCheckComments setState:[defaults boolForKey:TurnOffCommentSpellCheckKey]];
    [self updateSpellingControlsFromDefaults:defaults];

    [dictionaryPopup addItemWithTitle: @"Automatic Language"];
    NSArray *theLanguages = [[NSSpellChecker sharedSpellChecker] availableLanguages];
    NSInteger numberOfItems = [theLanguages count];
    NSInteger i = 0;
    while (i < numberOfItems)
    {
        [dictionaryPopup addItemWithTitle: [theLanguages objectAtIndex: i]];
        i = i + 1;
    }
    BOOL useAutomatic = [defaults boolForKey: spellingAutomaticDefaultKey];
    NSString *myLanguage = [defaults objectForKey: spellingLanguageDefaultKey];
    if (useAutomatic)
        [dictionaryPopup selectItemAtIndex: 0];
    else
    {
        i = 0;
        while (i < numberOfItems)
            {
            if ( [myLanguage isEqualToString: [dictionaryPopup itemTitleAtIndex: (i + 1)]])
                  [dictionaryPopup selectItemAtIndex: (i + 1)];
                  i = i + 1;
            }
    }
    
    [_blockCursorButton setState: [defaults boolForKey:BlockCursorKey]];
    [_macroButton setState: [defaults boolForKey:SameFontForMacroKey]];
    NSColor *BlockCursorColor = [NSColor colorWithCalibratedRed: [defaults floatForKey:BlockCursorRKey]
        green: [defaults floatForKey:BlockCursorGKey] blue: [defaults floatForKey:BlockCursorBKey] alpha:1.0];
    [BlockCursorColorWell setColor:BlockCursorColor];
    
	[_alwaysHighlightButton setState:![defaults boolForKey:AlwaysHighlightEnabledKey]]; // added by Terada
	[_showIndicatorForMoveButton setState:[defaults boolForKey:ShowIndicatorForMoveEnabledKey]]; // added by Terada
	[_highlightContentButton setState:[defaults boolForKey:HighlightContentEnabledKey]]; // added by Terada
	[_beepButton setState:[defaults boolForKey:BeepEnabledKey]]; // added by Terada
	[_flashBackgroundButton setState:[defaults boolForKey:FlashBackgroundEnabledKey]]; // added by Terada
	[_checkBraceButton setState:[defaults boolForKey:CheckBraceEnabledKey]]; // added by Terada
	[_checkBracketButton setState:[defaults boolForKey:CheckBracketEnabledKey]]; // added by Terada
	[_checkSquareBracketButton setState:[defaults boolForKey:CheckSquareBracketEnabledKey]]; // added by Terada
	[_checkParenButton setState:[defaults boolForKey:CheckParenEnabledKey]]; // added by Terada
	[_showTabCharacterButton setState:[defaults boolForKey:showTabCharacterKey]]; // added by Terada
	[_showSpaceCharacterButton setState:[defaults boolForKey:showSpaceCharacterKey]]; // added by Terada
	[_showFullwidthSpaceCharacterButton setState:[defaults boolForKey:showFullwidthSpaceCharacterKey]]; // added by Terada
	[_showNewLineCharacterButton setState:[defaults boolForKey:showNewLineCharacterKey]]; // added by Terada
    [self updateInvisibleCharacterControls:defaults];
	[_makeatletterButton setState:[defaults boolForKey:MakeatletterEnabledKey]]; // added by Terada
	[_expl3SyntaxColorButton setState:[defaults boolForKey:expl3SyntaxColoringKey]];
	[_autoSaveEnabledButton setState:[defaults boolForKey:AutoSaveEnabledKey]];
	[_keepBackupButton setState:[defaults boolForKey:KeepBackupKey]];
	_keepBackupButton.enabled = ![defaults boolForKey:AutoSaveEnabledKey];
	[_saveEncodingMenuButton setState:[defaults boolForKey:EncodingMenuInSaveDialogKey]];

	NSString *kpsetool = [defaults objectForKey:KpsetoolKey];
	if (!kpsetool || [kpsetool isEqualToString:@""]) {
		kpsetool = @"kpsetool -w -n latex tex";
	}
	[_kpsetoolField setStringValue:kpsetool]; // added by Terada
	
	NSString *bibTeXengine = [defaults objectForKey:BibTeXengineKey];
	if (!bibTeXengine || [bibTeXengine isEqualToString:@""]) {
		bibTeXengine = @"bibtex";
	}
	[_bibTeXengineField setStringValue:bibTeXengine]; // added by Terada
	
/*
	NSColor *sourceBackgroundColor = [NSColor colorWithCalibratedRed: [defaults floatForKey:background_RKey]
		green: [defaults floatForKey:background_GKey] blue: [defaults floatForKey:background_BKey] alpha:1.0];
	[_sourceBackgroundColorWell setColor:sourceBackgroundColor];
    
    NSColor *sourceTextColor = [NSColor colorWithCalibratedRed: [defaults floatForKey:foreground_RKey]
                                                               green: [defaults floatForKey:foreground_GKey] blue: [defaults floatForKey:foreground_BKey] alpha:1.0];
	[_sourceTextColorWell setColor:sourceTextColor];
	
	NSColor *previewBackgroundColor = [NSColor colorWithCalibratedRed: [defaults floatForKey:PdfPageBack_RKey]
		green: [defaults floatForKey:PdfPageBack_GKey] blue: [defaults floatForKey:PdfPageBack_BKey] alpha:1.0];
	[_previewBackgroundColorWell setColor:previewBackgroundColor];
	
	NSColor *consoleBackgroundColor = [NSColor colorWithCalibratedRed: [defaults floatForKey:ConsoleBackgroundColor_RKey]
		green: [defaults floatForKey:ConsoleBackgroundColor_GKey] blue: [defaults floatForKey:ConsoleBackgroundColor_BKey] alpha:1.0];
	[_consoleBackgroundColorWell setColor:consoleBackgroundColor];
	
	NSColor *consoleForegroundColor = [NSColor colorWithCalibratedRed: [defaults floatForKey:ConsoleForegroundColor_RKey]
		green: [defaults floatForKey:ConsoleForegroundColor_GKey] blue: [defaults floatForKey:ConsoleForegroundColor_BKey] alpha:1.0];
	[_consoleForegroundColorWell setColor:consoleForegroundColor];
	
	NSColor *highlightBracesColor = [NSColor colorWithCalibratedRed: [defaults floatForKey:highlightBracesRedKey]
		green: [defaults floatForKey:highlightBracesGreenKey] blue: [defaults floatForKey:highlightBracesBlueKey] alpha:1.0];
	[_highlightBracesColorWell setColor:highlightBracesColor];
 
 */
    
	if ([defaults boolForKey:ConsoleWidthResizeKey] == YES) 
		[_consoleResizeMatrix selectCellWithTag:0];
	else 
		[_consoleResizeMatrix selectCellWithTag:1];
    
    if ( [defaults boolForKey:SourceAndPreviewInSameWindowKey])
      //  NSLog(@"onewindow is no");
    
        [useOneWindowButton setState:1];
    else
        [useTwoWindowsButton setState:1];
    
    if ( [defaults boolForKey:SwitchSidesKey])
        //  NSLog(@"onewindow is no");
        
        [useRightSourceButton setState:1];
    else
        [useLeftSourceButton setState:1];
    
    [XMLchapter setState: [defaults boolForKey: XMLChapterTagKey]];
    [XMLsection setState: [defaults boolForKey: XMLSectionTagKey]];
    [XMLsubsection setState: [defaults boolForKey: XMLSubsectionTagKey]];
    [XMLsubsubsection setState: [defaults boolForKey: XMLSubsubsectionTagKey]];
    [XMLintroduction setState: [defaults boolForKey: XMLIntroductionTagKey]];
    [XMLconclusion setState: [defaults boolForKey: XMLConclusionTagKey]];
    [XMLexercises setState: [defaults boolForKey: XMLExercisesTagKey]];
    [XMLproject setState: [defaults boolForKey: XMLProjectTagKey]];
    [XMLfigure setState: [defaults boolForKey: XMLFigureTagKey]];
    [XMLtable setState: [defaults boolForKey: XMLTableTagKey]];
    [XMLmark setState: [defaults boolForKey: XMLMarkTagKey]];

	// Create the contents of the encoding menu on the fly & select the active encoding
	[_defaultEncodeMatrix removeAllItems];
	[[TSEncodingSupport sharedInstance] addEncodingsToMenu:[_defaultEncodeMatrix menu] withTarget:0 action:0];
	[_defaultEncodeMatrix selectItemWithTag: [[TSEncodingSupport sharedInstance] defaultEncoding]];
    
    [_openAsTabsMatrix selectItemWithTag: [defaults integerForKey: OpenAsTabsKey]];

	if ([[defaults stringForKey:CommandCompletionCharKey] isEqualToString: @"ESCAPE"])
		[_commandCompletionMatrix selectCellWithTag:0];
	else 
		[_commandCompletionMatrix selectCellWithTag:1];
    
    if ([[defaults stringForKey:BlockWidthKey] isEqualToString: @"0"])
        [_blockWidthMatrix selectCellWithTag:0];
    else
        [_blockWidthMatrix selectCellWithTag:1];
    
    if ([[defaults stringForKey:BlockSideKey] isEqualToString: @"0"])
        [_blockSideMatrix selectCellWithTag:0];
    else if ([[defaults stringForKey:BlockSideKey] isEqualToString: @"1"])
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
    
	[_savePSButton setState:[defaults boolForKey:SavePSEnabledKey]];
	[_scrollButton setState:[defaults boolForKey:NoScrollEnabledKey]];
    [_consoleWindowPosMatrix selectCellWithTag:[defaults integerForKey:ConsoleWindowPosModeKey]];
    if ([defaults integerForKey:ConsoleWindowPosModeKey] == 0)
        [_consoleWindowPosButton setEnabled: YES];
    else
        [_consoleWindowPosButton setEnabled: NO];
    
	[_pdfWindowPosMatrix selectCellWithTag:[defaults integerForKey:PdfWindowPosModeKey]];
	/* koch: */
	if ([defaults integerForKey:PdfWindowPosModeKey] == 0)
		[_pdfWindowPosButton setEnabled: YES];
	else
		[_pdfWindowPosButton setEnabled: NO];
    
    [_htmlWindowPosMatrix selectCellWithTag:[defaults integerForKey:HtmlWindowPosModeKey]];
    /* koch: */
    if ([defaults integerForKey:HtmlWindowPosModeKey] == 0)
        [_htmlWindowPosButton setEnabled: YES];
    else
        [_htmlWindowPosButton setEnabled: NO];

	magnification = [defaults floatForKey:PdfMagnificationKey];
	mag = round(magnification * 100.0);
	myNumber = [NSNumber numberWithInteger:mag];
	[_magTextField setStringValue:[myNumber stringValue]];
	//      [_magTextField setIntValue: mag];


#ifdef MITSU_PDF

	myTag = [defaults integerForKey:PdfFirstPageStyleKey];
	if (!myTag) myTag = PDF_FIRST_RIGHT;
	[_firstPageMatrix selectCellWithTag:myTag];
    [_displayAsBookButton setState:[defaults boolForKey:DisplayAsBookKey] ? NSControlStateValueOn : NSControlStateValueOff];

	// mitsu 1.29 (O)
	NSInteger itemIndex;
	myTag = [defaults integerForKey:PdfPageStyleKey];
	if (!myTag) myTag = PDF_SINGLE_PAGE_STYLE; // default PdfPageStyleKey
	itemIndex = [_pageStylePopup indexOfItemWithTag: myTag];
	if (itemIndex == -1) itemIndex = 2; // default PdfPageStyleKey
	[_pageStylePopup selectItemAtIndex: itemIndex];

	myTag = [defaults integerForKey:PdfKitFitSizeKey];
	if (!myTag) myTag = NEW_PDF_FIT_TO_WINDOW; // default PdfKitFitSizeKey
	itemIndex = [_resizeOptionPopup indexOfItemWithTag: myTag];
	if (itemIndex == -1) itemIndex = 2; // default PdfKitFitSizeKey
	[_resizeOptionPopup selectItemAtIndex: itemIndex];

	myTag = [defaults integerForKey:PdfCopyTypeKey];
	if (!myTag) myTag = IMAGE_TYPE_JPEG_MEDIUM; // default PdfCopyTypeKey
	itemIndex = [_imageCopyTypePopup indexOfItemWithTag: myTag];
	if (itemIndex == -1) itemIndex = 1; // default PdfCopyTypeKey
	[_imageCopyTypePopup selectItemAtIndex: itemIndex];

	myTag = [defaults integerForKey:PdfKitMouseModeKey];
	if (!myTag) myTag = NEW_MOUSE_MODE_SELECT_TEXT; // default PdfKitMouseModeKey
	itemIndex = [_mouseModePopup indexOfItemWithTag: myTag];
	if (itemIndex == -1) itemIndex = 1; // default PdfKitMouseModeKey
	[_mouseModePopup selectItemAtIndex: itemIndex];

	[_colorMapButton setState: [SUD boolForKey:PdfColorMapKey]?NSOnState:NSOffState];
    
    /*
	NSColor *aColor;
	if ([SUD stringForKey:PdfFore_RKey]) {
		aColor = [NSColor colorWithCalibratedRed: [SUD floatForKey:PdfFore_RKey]
										   green: [SUD floatForKey:PdfFore_GKey] blue: [SUD floatForKey:PdfFore_BKey]
										   alpha: [SUD floatForKey:PdfFore_AKey]];
	}
	else
		aColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
	[_copyForeColorWell setColor: aColor];
	[_copyForeColorWell setContinuous: YES];

	if ([SUD stringForKey:PdfBack_RKey]) {
		aColor = [NSColor colorWithCalibratedRed: [SUD floatForKey:PdfBack_RKey]
										   green: [SUD floatForKey:PdfBack_GKey] blue: [SUD floatForKey:PdfBack_BKey]
										   alpha: [SUD floatForKey:PdfBack_AKey]];
	}
	else
		aColor = [NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1];
	[_copyBackColorWell setColor: aColor];
	[_copyBackColorWell setContinuous: YES];
*/
    
	myTag = [defaults integerForKey:PdfColorParam1Key];
	itemIndex = [_colorParam1Popup indexOfItemWithTag: myTag];
	if (itemIndex == -1) itemIndex = 2; // default idx = 2
	[_colorParam1Popup selectItemAtIndex: itemIndex];

//	[_defaultBibtexMatrix selectCellWithTag: myTag]; // comment out by Terada

	myTag = [defaults integerForKey:DistillerCommandKey];
	[_distillerMatrix selectCellWithTag: myTag];
	
    /*
	myBool = [defaults boolForKey:BringPdfFrontOnTypesetKey];
	if (myBool == YES)
		myTag = 0;
	else
		myTag = 1;
	[_afterTypesettingMatrix selectCellWithTag: myTag];
	*/
    myInteger = [defaults integerForKey:BringFrontOnTypesetKey];
    myTag = myInteger;
    [_afterTypesettingMatrix selectCellWithTag: myTag];


	// end mitsu 1.29
#endif

	tabSize = [defaults integerForKey: tabsKey];
	myNumber = [NSNumber numberWithInteger:tabSize];
    [tabIndentField setStringValue:[myNumber stringValue]];
    
    // [firstParagraphIndentField setStringValue:[defaults stringForKey: SourceFirstLineHeadIndentKey]];
    // [remainingParagraphIndentField setStringValue:[defaults stringForKey: SourceHeadIndentKey]];
    // [interlineSpacingField setStringValue:[defaults stringForKey: SourceInterlineSpaceKey]];
    
    [firstParagraphIndentField setIntegerValue:[defaults integerForKey: SourceFirstLineHeadIndentKey]];
    [remainingParagraphIndentField setIntegerValue:[defaults integerForKey: SourceHeadIndentKey]];
    if ([defaults integerForKey: SourceInterlineSpaceKey] == 0)
        [interlineSpacingField setIntegerValue: 1];
    else
        [interlineSpacingField setIntegerValue:[defaults integerForKey: SourceInterlineSpaceKey]];

	[_texCommandTextField setStringValue:[defaults stringForKey:TexCommandKey]];
	[_latexCommandTextField setStringValue:[defaults stringForKey:LatexCommandKey]];
	[_texGSCommandTextField setStringValue:[defaults stringForKey:TexGSCommandKey]];
	[_latexGSCommandTextField setStringValue:[defaults stringForKey:LatexGSCommandKey]];
	[_tetexBinPathField setStringValue:[defaults stringForKey:TetexBinPath]];
    [_HtmlHomeField setStringValue:[defaults stringForKey:HtmlHomeKey]];
    [_altPathField setStringValue:[defaults stringForKey:AltPathKey]];
	[_gsBinPathField setStringValue:[defaults stringForKey:GSBinPath]];

	[_texScriptCommandTextField setStringValue:[defaults stringForKey:TexScriptCommandKey]];
	[_latexScriptCommandTextField setStringValue:[defaults stringForKey:LatexScriptCommandKey]];
    [_alternateEngineTextField setStringValue:[defaults stringForKey:AlternateEngineKey]];

	[_defaultCommandMatrix selectCellWithTag:[defaults integerForKey:DefaultCommandKey]];
	[_engineTextField setStringValue:[defaults stringForKey:DefaultEngineKey]];
	if ([defaults integerForKey:DefaultCommandKey] == 2) {
		[_engineTextField setEnabled: YES];
		[_engineTextField setEditable: YES];
		[_engineTextField setSelectable: YES];
		[_engineTextField selectText:self];
	}
	else
		[_engineTextField setEnabled: NO];

	if ([defaults integerForKey:DefaultCommandKey] == 2)
		[_engineTextField setEditable: YES];
	[_defaultScriptMatrix selectCellWithTag:[defaults integerForKey:DefaultScriptKey]];
	// The methods that use Pdf Sync (PDFSYNC and SEARCHFIRST) no longer have a
	// button. If one is still set, select no button rather than leaving a stale
	// selection.
	if (! [_syncMatrix selectCellWithTag:[defaults integerForKey:SyncMethodKey]]) {
		[_syncMatrix setAllowsEmptySelection: YES];
		[_syncMatrix deselectAllCells];
		[_syncMatrix setAllowsEmptySelection: NO];
	}
	[_saveRelatedButton setState:[defaults boolForKey:SaveRelatedKey]];
    [_useTransparencyButton setState:[defaults boolForKey:UseTransparencyKey]];
    [_syncTabButton setState:[defaults boolForKey:SyncUseTabsKey]];
}

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
