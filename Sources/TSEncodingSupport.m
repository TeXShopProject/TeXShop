/*
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
 * $Id: TSEncodingSupport.m 254 2007-06-03 21:09:25Z fingolfin $
 *
 * Created by Mitsuhiro Shishikura on Fri Dec 13 2002.
 *
 */

#import "TSEncodingSupport.h"
#import "TSDocument.h" // mitsu 1.29 (P)
#import "globals.h"
#import "GlobalData.h"
#import "NSString-Extras.h"  //Terada
#include <sys/xattr.h>

static NSString *yenString = nil;

@implementation TSEncodingSupport

// Pointer to the TSEncodingSupport singleton
static id sharedEncodingSupport = nil;

// We pair CFStringEncoding with custom names
typedef struct {
	NSStringEncoding	nsEnc;
	CFStringEncoding	cfEnc;
    //	NSString			*name;
} TSEncoding;


// List of the supported encodings.
static TSEncoding _availableEncodings[] = {
	{ 0, kCFStringEncodingMacRoman }, //			@"MacOSRoman" },
	{ 0, kCFStringEncodingISOLatin1}, //			@"IsoLatin" },
	{ 0, kCFStringEncodingISOLatin2}, //			@"IsoLatin2" },
	{ 0, kCFStringEncodingISOLatin5}, //			@"IsoLatin5" },
	{ 0, kCFStringEncodingISOLatin9}, //			@"IsoLatin9" },
	{ 0, kCFStringEncodingISOLatinGreek}, //		@"IsoLatinGreek" }, //Greek ISO 8859-7
	{ 0, kCFStringEncodingMacCentralEurRoman}, //	@"Mac Central European Roman" }, // added at request of Czech Republic respondent
	{ 0, kCFStringEncodingMacJapanese}, //			@"MacJapanese" },
	{ 0, kCFStringEncodingDOSJapanese}, //			@"DOSJapanese" },
	{ 0, kCFStringEncodingShiftJIS_X0213_00}, //	@"SJIS_X0213" },
	{ 0, kCFStringEncodingEUC_JP}, //				@"EUC_JP" },
	{ 0, kCFStringEncodingISO_2022_JP}, //			@"JISJapanese" },
	{ 0, kCFStringEncodingMacKorean}, //			@"MacKorean" },
    { 0, kCFStringEncodingDOSKorean}, //			@"DOSKorean" },
	{ 0, kCFStringEncodingUTF8}, //					@"UTF-8 Unicode" },
	{ 0, kCFStringEncodingUnicode}, //				@"Standard Unicode" },
	{ 0, kCFStringEncodingMacCyrillic}, //			@"Mac Cyrillic" },
	{ 0, kCFStringEncodingDOSCyrillic}, //			@"DOS Cyrillic" },
	{ 0, kCFStringEncodingDOSRussian}, //			@"DOS Russian" },
	{ 0, kCFStringEncodingWindowsLatin1}, //		@"Windows Latin 1" }, // code page 1252
	{ 0, kCFStringEncodingWindowsLatin2}, //		@"WindowsCentralEurRoman" }, // code page 1250
	{ 0, kCFStringEncodingWindowsCyrillic}, //		@"Windows Cyrillic" },
	{ 0, kCFStringEncodingKOI8_R}, //				@"KOI8_R" },
	{ 0, kCFStringEncodingMacChineseTrad}, //		@"Mac Chinese Traditional" },
	{ 0, kCFStringEncodingMacChineseSimp}, //		@"Mac Chinese Simplified" },
	{ 0, kCFStringEncodingDOSChineseTrad}, //		@"DOS Chinese Traditional" },
	{ 0, kCFStringEncodingDOSChineseSimplif}, //	@"DOS Chinese Simplified" },
	{ 0, kCFStringEncodingGBK_95}, //				@"GBK" },
	{ 0, kCFStringEncodingGB_2312_80}, //			@"GB 2312" },
	{ 0, kCFStringEncodingGB_18030_2000}, //		@"GB 18030" },
    { 0, kCFStringEncodingASCII}, //
};

// List of the supported encodings.
static TSEncoding _availableTexworksEncodings[] = {
    { 0, kCFStringEncodingMacRoman }, //			@"MacOSRoman" },
    { 0, kCFStringEncodingISOLatin1}, //			@"IsoLatin" },
    { 0, kCFStringEncodingISOLatin2}, //			@"IsoLatin2" },
    { 0, kCFStringEncodingISOLatin5}, //			@"IsoLatin5" },
    { 0, kCFStringEncodingISOLatin9}, //			@"IsoLatin9" },
    { 0, kCFStringEncodingISOLatinGreek}, //		@"IsoLatinGreek" }, //Greek ISO 8859-7
    { 0, kCFStringEncodingMacCentralEurRoman}, //	@"Mac Central European Roman" }, // added at request of Czech Republic respondent
    { 0, kCFStringEncodingShiftJIS_X0213_00}, //	@"SJIS_X0213" },
    { 0, kCFStringEncodingEUC_JP}, //				@"EUC_JP" },
    { 0, kCFStringEncodingUTF8}, //					@"UTF-8 Unicode" },
    { 0, kCFStringEncodingUnicode}, //				@"Standard Unicode" },
    { 0, kCFStringEncodingWindowsLatin1}, //		@"Windows Latin 1" }, // code page 1252
    { 0, kCFStringEncodingWindowsLatin2}, //		@"WindowsCentralEurRoman" }, // code page 1250
    { 0, kCFStringEncodingWindowsCyrillic}, //		@"Windows Cyrillic" },
    { 0, kCFStringEncodingKOI8_R}, //				@"KOI8_R" },
    { 0, kCFStringEncodingGB_18030_2000}, //		@"GB 18030" },
//    { 0, kCFStringEncodingASCII}, //
};




+ (void)initialize
{
	// Conver the CF encodings to NS encodings.
	NSInteger i;
	for (i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
		_availableEncodings[i].nsEnc = CFStringConvertEncodingToNSStringEncoding(_availableEncodings[i].cfEnc);
    
    for (i = 0; i < ARRAYSIZE(_availableTexworksEncodings); ++i)
        _availableTexworksEncodings[i].nsEnc = CFStringConvertEncodingToNSStringEncoding(_availableTexworksEncodings[i].cfEnc);

	// initialize yen string
	unichar yenChar = YEN;
	yenString = [NSString stringWithCharacters: &yenChar length:1];
}

+ (id)sharedInstance
{
	if (sharedEncodingSupport == nil) {
		sharedEncodingSupport = [[TSEncodingSupport alloc] init];
	}
	return sharedEncodingSupport;
}

- (id)init
{
    NSMutableArray  *myArray;
    NSMutableArray  *texWorksArray;
    
	if (sharedEncodingSupport) {
		// [super dealloc];
	} else {
		sharedEncodingSupport = [super init];
        
       myArray = [NSMutableArray arrayWithObjects: @"MacOSRoman", @"IsoLatin", @"IsoLatin2", @"IsoLatin5", @"IsoLatin9", @"IsoLatinGreek", @"Mac Central European Roman", @"MacJapanese", @"DOSJapanese", @"SJIS_X0213", @"EUC_JP", @"JISJapanese", @"MacKorean", @"DOSKorean", @"UTF-8 Unicode", @"Standard Unicode", @"Mac Cyrillic", @"DOS Cyrillic", @"DOS Russian", @"Windows Latin 1", @"WindowsCentralEurRoman", @"Windows Cyrillic", @"KOI8_R", @"Mac Chinese Traditional", @"Mac Chinese Simplified", @"DOS Chinese Traditional", @"DOS Chinese Simplified", @"GBK", @"GB 2312", @"GB 18030", @"Ascii", nil];
        
        
        texWorksArray = [NSMutableArray arrayWithObjects:  @"Apple Roman", @"ISO 8859-1", @"ISO 8859-2", @"ISO 8859-9", @"ISO 8859-15", @"ISO 8859-7", @"macce", @"Shift-JIS", @"EUC_JP", @"UTF-8", @"UTF-16", @"ansinew", @"Windows-1250", @"Windows-1251", @"KOI8-R", @"GB18030-0", nil];
        
        self.availableEncodingsNames = myArray;
        self.availableTexworksEncodingNames = texWorksArray;
        self.defaultEncodingNumber = 4; // ISOLatin9


		g_shouldFilter = kNoFilterMode;

		// register for encoding changed notification
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(encodingChanged:)
				name:@"EncodingChangedNotification" object:nil];

		// Here preferences are set for the state of the pasteboard conversion facility, which is only used with Japanese encoding.
		if ([SUD objectForKey: @"ConvertToBackslash"] == nil)
			[SUD setBool: NO forKey: @"ConvertToBackslash"];
		if ([SUD objectForKey: @"ConvertToYen"] == nil)
			[SUD setBool: YES forKey: @"ConvertToYen"];
	}
	return sharedEncodingSupport;
}

/*
- (void)dealloc
{
	if (self != sharedEncodingSupport)
		[super dealloc];	// Don't free our shared instance
}
*/

// Delegate method for text fields
- (void)controlTextDidChange:(NSNotification *)note
{
	NSText *fieldEditor = [[note userInfo] objectForKey: @"NSFieldEditor"];
	if (!fieldEditor)
		return;
	NSString *oldString = [fieldEditor string];
	NSRange selectedRange = [fieldEditor selectedRange];
	NSString *newString;

	if (g_shouldFilter == kMacJapaneseFilterMode) {
		newString = filterBackslashToYen(oldString);
		[fieldEditor setString: newString];
		[fieldEditor setSelectedRange: selectedRange];
	} else if (g_shouldFilter == kOtherJapaneseFilterMode) {
		newString = filterYenToBackslash(oldString);
		[fieldEditor setString: newString];
		[fieldEditor setSelectedRange: selectedRange];
	}
}


// set up g_texChar, g_taggedTeXSections and menu item for tex character conversion
// FIXME: This is only called when starting up or when the encoding prefs are changed.
// In particular, it is *not* sufficient to just save a file with a different encoding!
// TODO: Correct this by making the encoding checks document specific. In particular,
// g_texChar, g_taggedTeXSections should be replaced by TSDocument members.
- (void)setupForEncoding
{
	NSString *currentEncoding;
	NSMenu *editMenu;
	id item;
	NSMutableString *menuTitle;
	TSDocument *theDoc;

	currentEncoding = [SUD stringForKey:EncodingKey];

	editMenu = [[[NSApp mainMenu] itemWithTitle:NSLocalizedString(@"Edit", @"Edit")] submenu];
	if (editMenu) {
		NSInteger i = [editMenu indexOfItemWithTarget:self andAction:@selector(toggleTeXCharConversion:)];
		if (i >= 0)	{ // remove menu item
			[editMenu removeItemAtIndex: i];
			if ([[editMenu itemAtIndex: i-1] isSeparatorItem])
				[editMenu removeItemAtIndex: i-1];
		}
	}

	if ([currentEncoding isEqualToString:@"MacJapanese"] ||
			[currentEncoding isEqualToString:@"SJIS_X0213"] ) {
		g_texChar = YEN; // yen
		// ARC [g_taggedTeXSections release];

		if ([SUD boolForKey: ConTeXtTagsKey]) {
			g_taggedTeXSections = [[NSArray alloc] initWithObjects:
					filterBackslashToYen(@"\\chapter"),
					filterBackslashToYen(@"\\section"),
					filterBackslashToYen(@"\\subsection"),
					filterBackslashToYen(@"\\subsubsection"),
					filterBackslashToYen(@"\\subsubsubsection"),
					filterBackslashToYen(@"\\subsubsubsubsection"),
					filterBackslashToYen(@"\\part"),
					filterBackslashToYen(@"\\title"),
					filterBackslashToYen(@"\\subject"),
					filterBackslashToYen(@"\\subsubject"),
					filterBackslashToYen(@"\\subsubsubject"),
					filterBackslashToYen(@"\\subsubsubsubject"),
					filterBackslashToYen(@"\\subsubsubsubsubject"),
					nil];
		}
        else {
            g_taggedTeXSections = [[NSArray alloc] initWithObjects:
                                   filterBackslashToYen(@"\\chapter"),
                                   filterBackslashToYen(@"\\part{"),
                                   filterBackslashToYen(@"\\section"),
                                   filterBackslashToYen(@"\\subsection"),
                                   filterBackslashToYen(@"\\subsubsection"),
                                   filterBackslashToYen(@"\\paragraph"),
                                   filterBackslashToYen(@"\\subparagraph"),
                                   filterBackslashToYen(@"\\frametitle"),
                                   filterBackslashToYen(@"% \\chapter"),
                                   filterBackslashToYen(@"% \\part{"),
                                   filterBackslashToYen(@"% \\section"),
                                   filterBackslashToYen(@"% \\subsection"),
                                   filterBackslashToYen(@"% \\subsubsection"),
                                   filterBackslashToYen(@"% \\paragraph"),
                                   filterBackslashToYen(@"% \\subparagraph"),
                                   filterBackslashToYen(@"% \\begin{macro}"),
                                   filterBackslashToYen(@"% \\begin{environment}"),
                                   // NDS - add powerdot support here
                                   filterBackslashToYen(@"\\begin{slide}"),
                                   filterBackslashToYen(@"\\begin{wideslide}"),
                                   filterBackslashToYen(@"\\begin{notes}"),
                                   filterBackslashToYen(@"\\begin{frame}"),
                                   // NDS end
                                   nil];
        }
 
				// mitsu 1.29 (P)

		// If the command completion list already exists, and we are about to change the filter mode:
		// Update the command completion list to match the new filter mode.
		if (g_shouldFilter != kMacJapaneseFilterMode && g_commandCompletionList) {
			[g_commandCompletionList replaceOccurrencesOfString: @"\\" withString: yenString
						options: 0 range: NSMakeRange(0, [g_commandCompletionList length])];
			theDoc = [[NSDocumentController sharedDocumentController]
				documentForFileName: [[GlobalData sharedGlobalData].CommandCompletionPath stringByStandardizingPath]];
			if (theDoc)
				[[theDoc textView] setString: filterBackslashToYen([[theDoc textView] string])];
		}
		// end mitsu 1.29
		g_shouldFilter = kMacJapaneseFilterMode;
		// set up menu item
		if (editMenu) {
			[editMenu addItem: [NSMenuItem separatorItem]];
			menuTitle = [NSMutableString stringWithString:
						NSLocalizedString(@"Convert \\yen to \\ in Pasteboard", @"Convert \\yen to \\ in Pasteboard")];
			[menuTitle replaceOccurrencesOfString: @"\\yen" withString: yenString
						options: 0 range: NSMakeRange(0, [menuTitle length])];
			item = [editMenu addItemWithTitle: menuTitle
					action:@selector(toggleTeXCharConversion:) keyEquivalent: @""];
			[item setTarget: self];
			[item setState: [SUD boolForKey: @"ConvertToBackslash"]?NSOnState:NSOffState];
		}
	} else {
		g_texChar = BACKSLASH;
		
		/*
		[g_taggedTeXSections release];
		g_taggedTeXSections = [[NSArray alloc] initWithObjects:
							@"\\chapter",
							@"\\section",
							@"\\subsection",
							@"\\subsubsection",
							nil];
		*/
				// mitsu 1.29 (P)
		// If the command completion list already exists, and we are about to change the filter mode:
		// Update the command completion list to match the new filter mode. {
		if (g_shouldFilter == kMacJapaneseFilterMode && g_commandCompletionList) {
			[g_commandCompletionList replaceOccurrencesOfString: yenString withString: @"\\"
						options: 0 range: NSMakeRange(0, [g_commandCompletionList length])];
			theDoc = [[NSDocumentController sharedDocumentController]
				documentForFileName: [[GlobalData sharedGlobalData].CommandCompletionPath stringByStandardizingPath]];
			if (theDoc)
				[[theDoc textView] setString: filterYenToBackslash([[theDoc textView] string])];
		}
		// end mitsu 1.29

		if ([currentEncoding isEqualToString:@"DOSJapanese"] ||
				[currentEncoding isEqualToString:@"EUC_JP"] ||
				[currentEncoding isEqualToString:@"JISJapanese"] ||
				([currentEncoding isEqualToString:@"UTF-8 Unicode"] && [SUD boolForKey:ptexUtfOutputEnabledKey]) )
		{
			g_shouldFilter = kOtherJapaneseFilterMode;
			// set up menu item
			if (editMenu) {
				[editMenu addItem: [NSMenuItem separatorItem]];
				menuTitle = [NSMutableString stringWithString:
								NSLocalizedString(@"Convert \\ to \\yen in Pasteboard", @"Convert \\ to \\yen in Pasteboard")];
				[menuTitle replaceOccurrencesOfString: @"\\yen" withString: yenString
							options: 0 range: NSMakeRange(0, [menuTitle length])];
				item = [editMenu addItemWithTitle: menuTitle
						action:@selector(toggleTeXCharConversion:) keyEquivalent: @""];
				[item setTarget: self];
				[item setState: [SUD boolForKey: @"ConvertToYen"]?NSOnState:NSOffState];
			}
		} else {
			g_shouldFilter = kNoFilterMode;
		}
	}
}

// called when the encoding is changed in Preferences dialog
- (void)encodingChanged: (NSNotification *)note
{
	[self setupForEncoding];

	[[NSNotificationCenter defaultCenter] postNotificationName:@"ResetTagsMenuNotification" object:self];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"DocumentSyntaxColorNotification" object:self];
	//[[NSNotificationCenter defaultCenter] postNotificationName:@"ReloadMacrosNotification" object:self];
}


// action for "Convert * to * in Pasteboard"
- (IBAction)toggleTeXCharConversion:(id)sender
{
	NSString *currentEncoding;
	NSString *theKey;

	currentEncoding = [SUD stringForKey:EncodingKey];
	if ([currentEncoding isEqualToString:@"MacJapanese"] ||
			[currentEncoding isEqualToString:@"SJIS_X0213"])
		theKey = @"ConvertToBackslash";
	else if ([currentEncoding isEqualToString:@"DOSJapanese"] ||
		[currentEncoding isEqualToString:@"EUC_JP"] ||
		[currentEncoding isEqualToString:@"JISJapanese"] ||
		([currentEncoding isEqualToString:@"UTF-8 Unicode"] && [SUD boolForKey:ptexUtfOutputEnabledKey]) )
		theKey = @"ConvertToYen";
	else
		return;
	[SUD setBool: ![SUD boolForKey: theKey]  forKey: theKey];
	[SUD synchronize];
	[(NSMenuItem *)sender setState: [SUD boolForKey: theKey]?NSOnState:NSOffState];
}

#pragma mark New encoding API

- (NSStringEncoding)defaultEncoding
{
	NSString	*currentEncoding;

	currentEncoding = [SUD stringForKey:EncodingKey];
	return [self stringEncodingForKey: currentEncoding];
}


- (NSStringEncoding)stringEncodingForKey: (NSString *)key
{

	NSInteger i;
	for (i = 0; i < ARRAYSIZE(_availableEncodings); ++i) {
//		if ([key isEqualToString:_availableEncodings[i].name])
        if ([key isEqualToString:self.availableEncodingsNames[i]])
			return _availableEncodings[i].nsEnc;
	}
    
    NSLog(@"no TeXShop code");

    for (i = 0; i < ARRAYSIZE(_availableTexworksEncodings); ++i) {
        //		if ([key isEqualToString:_availableEncodings[i].name])
        if ([key isEqualToString:self.availableTexworksEncodingNames[i]])
            return _availableTexworksEncodings[i].nsEnc;
    }

    
	// In 2.18, the old name CentralEurRoman was changed to the new name Mac Central European Roman
	// Unfortunately, members of Mathematical Institute of Silesian University in Opava, Czech Republic, Europe had
	// hundreds of documents with encoding set by %!TEX encoding = CentralEurRoman
	// We special case that name for those folks!
	if ([key isEqualToString: @"CentralEurRoman"]) 
			return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingMacCentralEurRoman);


	// If the encoding is unknown, use the default encoding in our list (Latin 9).
    NSRunAlertPanel(NSLocalizedString(@"Error", @"Error"),
                    NSLocalizedString(@"Unknown encoding; using Latin 9.", @"Unknown encoding; using Latin 9."),
                    nil, nil, nil);

    return _availableEncodings[self.defaultEncodingNumber].nsEnc;
	// return _availableEncodings[0].nsEnc;
}

- (NSString *)keyForStringEncoding: (NSStringEncoding)encoding
{
	NSInteger i;
	for (i = 0; i < ARRAYSIZE(_availableEncodings); ++i) {
		if (_availableEncodings[i].nsEnc == encoding)
			return self.availableEncodingsNames[i];
	}
	// If the encoding is unknown, use the default encoding in our list (Latin 9).
    NSRunAlertPanel(NSLocalizedString(@"Error", @"Error"),
                    NSLocalizedString(@"Unknown encoding; using Latin 9.", @"Unknown encoding; using Latin 9."),
                    nil, nil, nil);
    return self.availableEncodingsNames[self.defaultEncodingNumber];
	// return self.availableEncodingsNames[0];
}

- (NSString *)localizedNameForKey: (NSString *)key
{
	return NSLocalizedStringFromTable(key, @"Encodings", @"Fetch localized encoding name");
}

- (NSString *)localizedNameForStringEncoding: (NSStringEncoding)encoding
{
	return [self localizedNameForKey: [self keyForStringEncoding:encoding]];
}

- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)aTarget action:(SEL)anAction
{
	id item;
	NSString *name;
	NSStringEncoding enc;
	NSInteger i;

	for (i = 0; i < ARRAYSIZE(_availableEncodings); ++i) {
		enc = _availableEncodings[i].nsEnc;
		name = [self localizedNameForKey:self.availableEncodingsNames[i]];

		item = [[NSMenuItem alloc] initWithTitle: name action:anAction keyEquivalent:@""];
		if (aTarget)
			[item setTarget: aTarget];
		[item setTag: enc];
		[menu addItem: item];
	}
}

#pragma mark Support for utf.sty

// zenitani and itoh, 1.35 (C) -- support for utf.sty
- (BOOL)isAvailableEncoding:(NSStringEncoding)encoding
{
	NSInteger i;
	for (i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
		if (_availableEncodings[i].nsEnc == encoding)
			return YES;
	return NO;
}

static BOOL TSDataDecodes(NSData *data, NSStringEncoding encoding)
{
	return [[NSString alloc] initWithData:data encoding:encoding] != nil;
}

// The encoding that TextEdit and other applications record in com.apple.TextEncoding,
// for example "utf-8;134217984" (an IANA name and a CFStringEncoding).
static NSStringEncoding TSRecordedEncoding(NSURL *url)
{
	if (! url.isFileURL)
		return 0;
	char buffer[256];
	ssize_t length = getxattr(url.fileSystemRepresentation, "com.apple.TextEncoding", buffer, sizeof(buffer) - 1, 0, 0);
	if (length <= 0)
		return 0;
	buffer[length] = 0;
	NSString *value = [NSString stringWithUTF8String:buffer];
	if (! value)
		return 0;
	NSArray *parts = [value componentsSeparatedByString:@";"];
	CFStringEncoding cfEncoding = kCFStringEncodingInvalidId;
	if (parts.count > 1 && [parts[1] length] > 0)
		cfEncoding = (CFStringEncoding)[parts[1] longLongValue];
	else
		cfEncoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)parts[0]);
	if (cfEncoding == kCFStringEncodingInvalidId || ! CFStringIsEncodingAvailable(cfEncoding))
		return 0;
	return CFStringConvertEncodingToNSStringEncoding(cfEncoding);
}

static NSArray *TSEncodingFamily(NSString *family)
{
	CFStringEncoding japanese[] = {kCFStringEncodingEUC_JP, kCFStringEncodingDOSJapanese, kCFStringEncodingShiftJIS_X0213_00, kCFStringEncodingMacJapanese};
	CFStringEncoding korean[] = {kCFStringEncodingDOSKorean, kCFStringEncodingMacKorean};
	CFStringEncoding simplified[] = {kCFStringEncodingGB_18030_2000, kCFStringEncodingMacChineseSimp};
	CFStringEncoding traditional[] = {kCFStringEncodingDOSChineseTrad, kCFStringEncodingMacChineseTrad};
	CFStringEncoding cyrillic[] = {kCFStringEncodingWindowsCyrillic, kCFStringEncodingKOI8_R, kCFStringEncodingMacCyrillic};
	CFStringEncoding central[] = {kCFStringEncodingWindowsLatin2, kCFStringEncodingISOLatin2, kCFStringEncodingMacCentralEurRoman};
	CFStringEncoding greek[] = {kCFStringEncodingISOLatinGreek};
	CFStringEncoding turkish[] = {kCFStringEncodingISOLatin5};
	CFStringEncoding western[] = {kCFStringEncodingWindowsLatin1, kCFStringEncodingMacRoman};
	CFStringEncoding *list = western; NSInteger count = 2;
	if ([family isEqualToString:@"ja"]) { list = japanese; count = 4; }
	else if ([family isEqualToString:@"ko"]) { list = korean; count = 2; }
	else if ([family isEqualToString:@"zh-Hans"]) { list = simplified; count = 2; }
	else if ([family isEqualToString:@"zh-Hant"]) { list = traditional; count = 2; }
	else if ([family isEqualToString:@"cyrillic"]) { list = cyrillic; count = 3; }
	else if ([family isEqualToString:@"central"]) { list = central; count = 3; }
	else if ([family isEqualToString:@"el"]) { list = greek; count = 1; }
	else if ([family isEqualToString:@"tr"]) { list = turkish; count = 1; }
	NSMutableArray *result = [NSMutableArray array];
	for (NSInteger i = 0; i < count; i++)
		[result addObject:@(CFStringConvertEncodingToNSStringEncoding(list[i]))];
	return result;
}

static NSString *TSFamilyForLanguage(NSString *language)
{
	NSString *code = [[language componentsSeparatedByString:@"-"] firstObject];
	if ([code isEqualToString:@"ja"] || [code isEqualToString:@"ko"] || [code isEqualToString:@"el"] || [code isEqualToString:@"tr"])
		return code;
	if ([code isEqualToString:@"zh"])
		return ([language containsString:@"Hant"] || [language hasSuffix:@"-TW"] || [language hasSuffix:@"-HK"] || [language hasSuffix:@"-MO"]) ? @"zh-Hant" : @"zh-Hans";
	if ([@[@"ru", @"uk", @"be", @"bg", @"sr", @"mk", @"kk"] containsObject:code])
		return @"cyrillic";
	if ([@[@"cs", @"pl", @"hu", @"sk", @"sl", @"hr", @"ro", @"bs"] containsObject:code])
		return @"central";
	return nil;
}

// How much a decoded text looks like Japanese. Bytes that are valid in two Japanese
// encodings often decode to plausible text in only one of them: the EUC-JP bytes of
// "kanpeki na gyuudon" (B4 B0 E0 FA A4 CA B5 ED D0 A7) also read as Shift JIS, but as
// half-width katakana mixed with rare kanji. Kana, common (JIS level 1) kanji and Japanese
// punctuation count for the text; half-width katakana, private use and control characters
// count against it. Only the first characters beyond ASCII are examined.
typedef struct { double score; NSUInteger kana, japanese, unlikely; } TSJapaneseScore;

static TSJapaneseScore TSScoreJapanese(NSString *text)
{
	TSJapaneseScore result = {0, 0, 0, 0};
	NSUInteger length = text.length, examined = 0;
	for (NSUInteger i = 0; i < length && examined < 4000; i++) {
		unichar c = [text characterAtIndex:i];
		if (c < 0x80)
			continue;
		examined++;
		if ((c >= 0x3041 && c <= 0x3096) || (c >= 0x30A1 && c <= 0x30FA) || c == 0x30FC) {
			result.score += 2; result.kana++; result.japanese++;
		} else if ((c >= 0x3000 && c <= 0x303F) || (c >= 0xFF01 && c <= 0xFF5E)) {
			result.score += 1; result.japanese++;
		} else if (c >= 0x4E00 && c <= 0x9FFF) {
			unsigned char bytes[4];
			NSUInteger used = 0;
			BOOL levelOne = [text getBytes:bytes maxLength:sizeof(bytes) usedLength:&used encoding:NSJapaneseEUCStringEncoding
								   options:0 range:NSMakeRange(i, 1) remainingRange:NULL]
				&& used == 2 && bytes[0] >= 0xB0 && bytes[0] <= 0xCF;
			result.score += levelOne ? 1.5 : 0.5;
			if (levelOne) result.japanese++;
		} else if (c >= 0xFF61 && c <= 0xFF9F) {
			result.score -= 2; result.unlikely++;
		} else if ((c >= 0xE000 && c <= 0xF8FF) || c < 0xA0) {
			result.score -= 3; result.unlikely++;
		} else {
			result.score -= 0.5;
		}
	}
	return result;
}

// The most plausible Japanese reading of data, among the Japanese encodings in TeXShop's list.
static NSStringEncoding TSBestJapaneseEncoding(NSData *data, TSJapaneseScore *best, BOOL (^available)(NSStringEncoding))
{
	NSStringEncoding result = 0;
	for (NSNumber *candidate in TSEncodingFamily(@"ja")) {
		NSStringEncoding encoding = candidate.unsignedIntegerValue;
		if (! available(encoding))
			continue;
		NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
		if (! text)
			continue;
		TSJapaneseScore score = TSScoreJapanese(text);
		if (! result || score.score > best->score) {
			result = encoding;
			*best = score;
		}
	}
	return result;
}

static BOOL TSIsSingleByteEncoding(NSStringEncoding encoding)
{
	return CFStringGetMaximumSizeForEncoding(1, CFStringConvertNSStringEncodingToEncoding(encoding)) == 1;
}

- (NSStringEncoding)detectedEncodingForData:(NSData *)data fileURL:(NSURL *)url preferredEncoding:(NSStringEncoding)preferred
{
	const unsigned char *bytes = data.bytes;
	NSUInteger length = data.length;

	// A byte order mark.
	if (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
		return NSUTF8StringEncoding;
	if (length >= 2 && ((bytes[0] == 0xFE && bytes[1] == 0xFF) || (bytes[0] == 0xFF && bytes[1] == 0xFE))
			&& [self isAvailableEncoding:NSUnicodeStringEncoding] && TSDataDecodes(data, NSUnicodeStringEncoding))
		return NSUnicodeStringEncoding;

	// 7-bit text reads the same in the preferred encoding, unless it is ISO-2022-JP,
	// which switches character sets with escape sequences such as ESC $ B.
	BOOL sevenBit = YES, kanjiEscape = NO;
	for (NSUInteger i = 0; i < length; i++) {
		if (bytes[i] >= 0x80) { sevenBit = NO; break; }
		if (bytes[i] == 0x1B && i + 2 < length && bytes[i + 1] == '$' && (bytes[i + 2] == 'B' || bytes[i + 2] == '@'))
			kanjiEscape = YES;
	}
	if (sevenBit)
		return (kanjiEscape && TSDataDecodes(data, NSISO2022JPStringEncoding)) ? NSISO2022JPStringEncoding : preferred;

	// The encoding recorded by the application that wrote the file.
	NSStringEncoding recorded = TSRecordedEncoding(url);
	if (recorded && [self isAvailableEncoding:recorded] && TSDataDecodes(data, recorded))
		return recorded;

	// Text with 8-bit bytes that is valid UTF-8 is almost certainly UTF-8.
	if (TSDataDecodes(data, NSUTF8StringEncoding))
		return NSUTF8StringEncoding;

	// Candidates: the preferred encoding, the encodings of its language and of the user's
	// languages, then the rest of TeXShop's list.
	NSMutableArray *families = [NSMutableArray array];
	for (NSString *family in @[@"ja", @"ko", @"zh-Hans", @"zh-Hant", @"cyrillic", @"central", @"el", @"tr"])
		if ([TSEncodingFamily(family) containsObject:@(preferred)])
			[families addObject:family];
	for (NSString *language in [NSLocale preferredLanguages]) {
		NSString *family = TSFamilyForLanguage(language);
		if (family && ! [families containsObject:family])
			[families addObject:family];
	}
	[families addObject:@"western"];
	NSMutableOrderedSet *candidates = [NSMutableOrderedSet orderedSetWithObject:@(preferred)];
	for (NSString *family in families)
		[candidates addObjectsFromArray:TSEncodingFamily(family)];
	NSInteger i;
	for (i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
		[candidates addObject:@(_availableEncodings[i].nsEnc)];
	NSMutableArray *suggested = [NSMutableArray array];
	for (NSNumber *candidate in candidates)
		if ([self isAvailableEncoding:candidate.unsignedIntegerValue])
			[suggested addObject:candidate];

	// Let Foundation weigh the candidates by how plausible the decoded text is.
	NSString *language = [[[[NSLocale preferredLanguages] firstObject] componentsSeparatedByString:@"-"] firstObject];
	NSMutableDictionary *options = [@{NSStringEncodingDetectionSuggestedEncodingsKey: suggested,
									  NSStringEncodingDetectionUseOnlySuggestedEncodingsKey: @YES,
									  NSStringEncodingDetectionAllowLossyKey: @NO} mutableCopy];
	if (language.length)
		options[NSStringEncodingDetectionLikelyLanguageKey] = language;
	NSString *converted = nil;
	BOOL lossy = NO;
	NSStringEncoding guess = [NSString stringEncodingForData:data encodingOptions:options convertedString:&converted usedLossyConversion:&lossy];
	// For very short data the guess may not even read the file.
	if (guess && ! TSDataDecodes(data, guess))
		guess = 0;

	BOOL (^available)(NSStringEncoding) = ^BOOL(NSStringEncoding encoding) { return [self isAvailableEncoding:encoding]; };
	TSJapaneseScore japanese = {0, 0, 0, 0};
	NSStringEncoding bestJapanese = TSBestJapaneseEncoding(data, &japanese, available);
	// Among the Japanese encodings, choose the reading that looks most like Japanese; on a tie
	// the earlier one in the family wins, so the Windows variant of Shift JIS, which TeX's
	// Japanese engines read, is preferred to the other Shift JIS variants.
	if (guess && [TSEncodingFamily(@"ja") containsObject:@(guess)] && bestJapanese)
		guess = bestJapanese;
	// A Western guess, or none, gives way when the Japanese reading is clearly Japanese text:
	// it has kana, a positive score and hardly any half-width katakana, private use or
	// control characters.
	else if (bestJapanese && (! guess || TSIsSingleByteEncoding(guess)) && japanese.kana > 0
			&& japanese.score > 0 && 4 * japanese.unlikely <= japanese.japanese) {
		guess = bestJapanese;
		lossy = NO;
	}

	if (guess && ! lossy && [self isAvailableEncoding:guess]) {
		// GB 18030 includes GBK and GB 2312; use it whenever it reads the file.
		NSStringEncoding gb18030 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
		if ((guess == CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGBK_95)
				|| guess == CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_2312_80)
				|| guess == CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSChineseSimplif))
				&& [self isAvailableEncoding:gb18030] && TSDataDecodes(data, gb18030))
			return gb18030;
		// Between two encodings with one byte per character, keep the preferred one.
		if (guess != preferred && TSIsSingleByteEncoding(guess) && TSIsSingleByteEncoding(preferred) && TSDataDecodes(data, preferred))
			return preferred;
		return guess;
	}

	for (NSNumber *candidate in suggested)
		if (TSDataDecodes(data, candidate.unsignedIntegerValue))
			return candidate.unsignedIntegerValue;
	return preferred;
}

- (BOOL)ptexUtfOutputCheck: (NSString *)dataString withEncoding: (NSStringEncoding)enc
{
	NSString *currentEncoding;
	currentEncoding = [self keyForStringEncoding:enc];

	if( ![dataString canBeConvertedToEncoding:
			CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISO_2022_JP)] ) {
		return YES;
	} else {
		return NO;
	}
}

- (NSData *)ptexUtfOutput: (NSTextView *)dataView withEncoding: (NSStringEncoding)enc
{
	NSString *dataString;
	
    dataString = [dataView string];
	NSMutableString *utfString, *newString = [NSMutableString string];
	NSRange charRange, aCIDRange;
	NSString *subString;
	NSGlyphInfo *aGlyph;
	NSUInteger startl, endl, end;
    
	charRange = NSMakeRange(0,1);
	endl = 0;
	while (charRange.location < [dataString length]) {
		if (charRange.location == endl) {
			[dataString getLineStart:&startl end:&endl contentsEnd:&end forRange:charRange];
			//            NSLog( @"%d %d %d", startl, end, endl);
		}
		//        NSLog( @"%d %d", charRange.length, charRange.location);
		charRange = [dataString rangeOfComposedCharacterSequenceAtIndex: charRange.location];
		//        NSLog( @"%d %d", charRange.length, charRange.location);
		subString = [dataString substringWithRange: charRange];
        
		if (![subString canBeConvertedToEncoding: CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISO_2022_JP)]) {
			aGlyph = [[dataView textStorage] attribute:NSGlyphInfoAttributeName
											   atIndex:charRange.location effectiveRange:&aCIDRange];
			if (aGlyph) {
				utfString = [NSMutableString stringWithFormat:@"%CCID{%ld}",
                             (unichar)g_texChar,(unsigned long)[aGlyph characterIdentifier]];
			} else if (charRange.length > 1) {
				NSLayoutManager *aLayout = [dataView layoutManager];
				utfString = [NSMutableString stringWithFormat:@"%CCID{%d}", (unichar)g_texChar,
                             [aLayout glyphAtIndex:charRange.location]];
				// 0x2014,0x2015 fix (reported by Kino-san)
			} else if ( [subString characterAtIndex: 0] == 0x2015) {
				utfString = [NSMutableString stringWithFormat:@"%C", (unichar)0x2014];
			} else {
				utfString = [NSMutableString stringWithFormat:@"%CUTF{%04X}",
                             (unichar)g_texChar, [subString characterAtIndex: 0]];
			}
			if ((charRange.location + charRange.length) == end) {
				[utfString appendString: @"%"];
			}
			[newString appendString: utfString];
		} else {
			[newString appendString: subString];
		}
		charRange.location += charRange.length;
		charRange.length = 1;
	}
    
    if ( [SUD boolForKey:AutomaticUTF8MACtoUTF8ConversionKey] )
        newString = [NSMutableString stringWithString:[newString normalizedStringWithModifiedNFC]];
    
	return [newString dataUsingEncoding:enc allowLossyConversion:YES];
}
// end 1.35 (C)


@end

// replace backslashes by yens
NSMutableString *filterBackslashToYen(NSString *aString)
{
	NSMutableString *newString = [NSMutableString stringWithString: aString];
	[newString replaceOccurrencesOfString: @"\\" withString: yenString
                                  options: 0 range: NSMakeRange(0, [newString length])];
	return newString;
}

// replace yens by backslashes
NSMutableString *filterYenToBackslash(NSString *aString)
{
	NSMutableString *newString = [NSMutableString stringWithString: aString];
	[newString replaceOccurrencesOfString: yenString withString: @"\\"
                                  options: 0 range: NSMakeRange(0, [newString length])];
	return newString;
}




