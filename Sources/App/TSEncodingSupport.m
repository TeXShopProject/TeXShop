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
	{ 0, kCFStringEncodingEUC_CN}, //				@"GB 2312" }, // kCFStringEncodingGB_2312_80 is the bare character set and does not read ASCII
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
        // An unknown encoding name falls back to UTF-8.
        for (NSInteger i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
            if (_availableEncodings[i].cfEnc == kCFStringEncodingUTF8)
                self.defaultEncodingNumber = i;


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


// YES if stringEncodingForKey: would find the key without falling back to Latin 9.
- (BOOL)knowsEncodingKey: (NSString *)key
{
	NSInteger i;
	for (i = 0; i < ARRAYSIZE(_availableEncodings); ++i)
		if ([key isEqualToString:self.availableEncodingsNames[i]])
			return YES;
	for (i = 0; i < ARRAYSIZE(_availableTexworksEncodings); ++i)
		if ([key isEqualToString:self.availableTexworksEncodingNames[i]])
			return YES;
	return [key isEqualToString: @"CentralEurRoman"];
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


	// If the encoding is unknown, use the default encoding in our list (UTF-8).
    NSRunAlertPanel(NSLocalizedString(@"Error", @"Error"),
                    NSLocalizedString(@"Unknown encoding; using UTF-8.", @"Unknown encoding; using UTF-8."),
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
	// If the encoding is unknown, use the default encoding in our list (UTF-8).
    NSRunAlertPanel(NSLocalizedString(@"Error", @"Error"),
                    NSLocalizedString(@"Unknown encoding; using UTF-8.", @"Unknown encoding; using UTF-8."),
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

// Whether data decodes in encoding and encodes back to the same bytes, so that saving
// the file unchanged writes the same file.
static BOOL TSDataRoundTrips(NSData *data, NSStringEncoding encoding)
{
	NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
	return text && [[text dataUsingEncoding:encoding allowLossyConversion:NO] isEqualToData:data];
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

static NSArray *TSEncodingList(const CFStringEncoding *list, NSInteger count)
{
	NSMutableArray *result = [NSMutableArray array];
	for (NSInteger i = 0; i < count; i++)
		[result addObject:@(CFStringConvertEncodingToNSStringEncoding(list[i]))];
	return result;
}

#define TSLIST(...) ({ static const CFStringEncoding list[] = {__VA_ARGS__}; TSEncodingList(list, sizeof(list) / sizeof(list[0])); })

// The encodings of a group of languages, most likely first.
static NSArray *TSEncodingFamily(NSString *family)
{
	if ([family isEqualToString:@"ja"])
		return TSLIST(kCFStringEncodingEUC_JP, kCFStringEncodingDOSJapanese, kCFStringEncodingMacJapanese, kCFStringEncodingShiftJIS_X0213_00);
	if ([family isEqualToString:@"ko"])
		return TSLIST(kCFStringEncodingDOSKorean, kCFStringEncodingMacKorean);
	if ([family isEqualToString:@"zh-Hans"])
		return TSLIST(kCFStringEncodingGB_18030_2000, kCFStringEncodingMacChineseSimp);
	if ([family isEqualToString:@"zh-Hant"])
		return TSLIST(kCFStringEncodingDOSChineseTrad, kCFStringEncodingMacChineseTrad);
	if ([family isEqualToString:@"cyrillic"])
		return TSLIST(kCFStringEncodingWindowsCyrillic, kCFStringEncodingKOI8_R, kCFStringEncodingMacCyrillic, kCFStringEncodingDOSRussian, kCFStringEncodingDOSCyrillic);
	if ([family isEqualToString:@"central"])
		return TSLIST(kCFStringEncodingWindowsLatin2, kCFStringEncodingISOLatin2, kCFStringEncodingMacCentralEurRoman);
	if ([family isEqualToString:@"el"])
		return TSLIST(kCFStringEncodingISOLatinGreek);
	if ([family isEqualToString:@"tr"])
		return TSLIST(kCFStringEncodingISOLatin5);
	return TSLIST(kCFStringEncodingWindowsLatin1, kCFStringEncodingISOLatin1, kCFStringEncodingISOLatin9, kCFStringEncodingMacRoman);
}

// Encodings that read the same text from the same bytes except for a few characters.
static NSArray *TSEncodingVariants(NSStringEncoding encoding)
{
	NSArray *groups = @[TSLIST(kCFStringEncodingDOSJapanese, kCFStringEncodingShiftJIS_X0213_00, kCFStringEncodingMacJapanese),
						TSLIST(kCFStringEncodingGB_18030_2000, kCFStringEncodingGBK_95, kCFStringEncodingEUC_CN, kCFStringEncodingDOSChineseSimplif, kCFStringEncodingMacChineseSimp),
						TSLIST(kCFStringEncodingDOSChineseTrad, kCFStringEncodingMacChineseTrad),
						TSLIST(kCFStringEncodingDOSKorean, kCFStringEncodingMacKorean)];
	for (NSArray *group in groups)
		if ([group containsObject:@(encoding)])
			return group;
	return @[];
}

static NSArray *TSFamiliesForLanguage(NSString *language)
{
	NSString *code = [[language componentsSeparatedByString:@"-"] firstObject];
	if ([code isEqualToString:@"ja"] || [code isEqualToString:@"ko"] || [code isEqualToString:@"el"] || [code isEqualToString:@"tr"])
		return @[code];
	if ([code isEqualToString:@"zh"])
		return @[([language containsString:@"Hant"] || [language hasSuffix:@"-TW"] || [language hasSuffix:@"-HK"] || [language hasSuffix:@"-MO"]) ? @"zh-Hant" : @"zh-Hans"];
	// Serbian and Bosnian are written in Cyrillic and in Latin letters.
	if ([code isEqualToString:@"sr"] || [code isEqualToString:@"bs"])
		return @[@"cyrillic", @"central"];
	if ([@[@"ru", @"uk", @"be", @"bg", @"mk", @"kk"] containsObject:code])
		return @[@"cyrillic"];
	if ([@[@"cs", @"pl", @"hu", @"sk", @"sl", @"hr", @"ro"] containsObject:code])
		return @[@"central"];
	return @[];
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

// The most plausible Japanese reading of data. Encodings that write the file back unchanged
// win over those that do not; on a tie the earlier encoding of the family wins, so the
// Windows variant of Shift JIS, which TeX's Japanese engines read, is preferred.
static NSStringEncoding TSBestJapaneseEncoding(NSData *data, TSJapaneseScore *best, BOOL (^available)(NSStringEncoding))
{
	NSStringEncoding result = 0;
	BOOL resultRoundTrips = NO;
	for (NSNumber *candidate in TSEncodingFamily(@"ja")) {
		NSStringEncoding encoding = candidate.unsignedIntegerValue;
		if (! available(encoding))
			continue;
		NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
		if (! text)
			continue;
		BOOL roundTrips = [[text dataUsingEncoding:encoding allowLossyConversion:NO] isEqualToData:data];
		TSJapaneseScore score = TSScoreJapanese(text);
		if (! result || (roundTrips && ! resultRoundTrips) || (roundTrips == resultRoundTrips && score.score > best->score)) {
			result = encoding;
			resultRoundTrips = roundTrips;
			*best = score;
		}
	}
	return result;
}

// How much a text decoded with a one-byte encoding looks like words: lower-case letters
// count for it, an upper-case letter starting a word a little, and an upper-case letter
// inside a lower-case word against it, as do C1 control characters, box drawing and
// other symbols. Common punctuation and currency signs are neutral.
typedef struct { double score; NSUInteger suspicious; } TSAlphabeticScore;

static TSAlphabeticScore TSScoreAlphabetic(NSString *text)
{
	NSCharacterSet *lower = [NSCharacterSet lowercaseLetterCharacterSet];
	NSCharacterSet *upper = [NSCharacterSet uppercaseLetterCharacterSet];
	NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
	NSString *neutral = @"\u00A0\u00AB\u00BB\u201E\u201C\u201D\u2018\u2019\u201A\u2013\u2014\u2026\u20AC\u00A7\u00B0\u00A9\u00AE\u00B7\u00BF\u00A1\u00A2\u00A3\u00A4\u00A5\u2116";
	TSAlphabeticScore result = {0, 0};
	unichar previous = ' ';
	NSUInteger length = text.length, examined = 0;
	for (NSUInteger i = 0; i < length && examined < 20000; i++) {
		unichar c = [text characterAtIndex:i];
		BOOL asciiLetter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
		BOOL previousAsciiLetter = (previous >= 'A' && previous <= 'Z') || (previous >= 'a' && previous <= 'z');
		BOOL greekOrCyrillic = c >= 0x0370 && c < 0x0530;
		BOOL previousGreekOrCyrillic = previous >= 0x0370 && previous < 0x0530;
		if (c < 0x80) {
			// An ASCII capital right after an accented lower-case letter is inside a word,
			// and a Latin letter right after a Greek or Cyrillic one mixes scripts in a word.
			if ((c >= 'A' && c <= 'Z' && previous >= 0x80 && [lower characterIsMember:previous])
					|| (asciiLetter && previousGreekOrCyrillic)) {
				result.score -= 1; result.suspicious++;
			}
			previous = c;
			continue;
		}
		examined++;
		if (greekOrCyrillic && previousAsciiLetter && [letters characterIsMember:c]) {
			result.score -= 1; result.suspicious++;
			previous = c;
			continue;
		}
		// Accented Latin letters seldom follow each other in words, while Cyrillic and Greek
		// letters do; a run of them is what Cyrillic bytes read as Latin look like.
		if (c >= 0x00C0 && c < 0x0250 && previous >= 0x00C0 && previous < 0x0250 && [letters characterIsMember:c] && [letters characterIsMember:previous]) {
			result.score -= 1;
			previous = c;
			continue;
		}
		if ([lower characterIsMember:c])
			result.score += 1;
		else if ([upper characterIsMember:c]) {
			if ([lower characterIsMember:previous]) { result.score -= 1; result.suspicious++; }
			else result.score += 0.5;
		} else if ([letters characterIsMember:c])
			result.score += 0.5;
		else if ([neutral rangeOfString:[NSString stringWithCharacters:&c length:1]].location == NSNotFound) {
			result.score -= 2; result.suspicious++;
		}
		previous = c;
	}
	return result;
}

// The one-byte encoding that \usepackage[...]{inputenc} declares in data, or 0. The last
// option is the one inputenc uses.
static NSStringEncoding TSInputencEncoding(NSData *data)
{
	NSString *text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)65536))] encoding:NSISOLatin1StringEncoding];
	NSRegularExpression *usepackage = [NSRegularExpression regularExpressionWithPattern:@"^[^%\\n]*\\\\usepackage\\s*\\[([^\\]]*)\\]\\s*\\{inputenc\\}" options:NSRegularExpressionAnchorsMatchLines error:NULL];
	NSTextCheckingResult *match = [usepackage firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
	if (! match)
		return 0;
	NSString *option = [[[[text substringWithRange:[match rangeAtIndex:1]] componentsSeparatedByString:@","] lastObject]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSDictionary *encodings = @{@"latin1": @(kCFStringEncodingISOLatin1), @"latin2": @(kCFStringEncodingISOLatin2),
								@"latin5": @(kCFStringEncodingISOLatin5), @"latin9": @(kCFStringEncodingISOLatin9),
								@"cp1250": @(kCFStringEncodingWindowsLatin2), @"cp1251": @(kCFStringEncodingWindowsCyrillic),
								@"cp1252": @(kCFStringEncodingWindowsLatin1), @"ansinew": @(kCFStringEncodingWindowsLatin1),
								@"koi8-r": @(kCFStringEncodingKOI8_R), @"cp866": @(kCFStringEncodingDOSRussian),
								@"cp855": @(kCFStringEncodingDOSCyrillic), @"applemac": @(kCFStringEncodingMacRoman),
								@"macce": @(kCFStringEncodingMacCentralEurRoman), @"maccyr": @(kCFStringEncodingMacCyrillic),
								@"macukr": @(kCFStringEncodingMacCyrillic)};
	NSNumber *cf = encodings[option];
	return cf ? CFStringConvertEncodingToNSStringEncoding((CFStringEncoding)cf.unsignedIntValue) : 0;
}

// Whether encoding is one of the one-byte encodings of TeXShop's list.
static BOOL TSIsSingleByteEncoding(NSStringEncoding encoding)
{
	for (NSString *family in @[@"western", @"cyrillic", @"central", @"el", @"tr"])
		if ([TSEncodingFamily(family) containsObject:@(encoding)])
			return YES;
	return encoding == NSASCIIStringEncoding;
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
	if (sevenBit) {
		if (kanjiEscape && TSDataDecodes(data, NSISO2022JPStringEncoding))
			return NSISO2022JPStringEncoding;
		// The default encoding is kept if it writes ASCII letters as ASCII; UTF-16 does not.
		NSData *sample = [@"Az09{}%" dataUsingEncoding:preferred];
		return [sample isEqualToData:[NSData dataWithBytes:"Az09{}%" length:7]] ? preferred : NSUTF8StringEncoding;
	}

	// The encoding recorded by the application that wrote the file.
	NSStringEncoding recorded = TSRecordedEncoding(url);
	if (recorded && [self isAvailableEncoding:recorded] && TSDataDecodes(data, recorded))
		return recorded;

	// Text with 8-bit bytes that is valid UTF-8 is almost certainly UTF-8.
	if (TSDataDecodes(data, NSUTF8StringEncoding))
		return NSUTF8StringEncoding;

	// The language groups of the preferred encoding and of the user's languages.
	NSMutableArray *families = [NSMutableArray array];
	for (NSString *family in @[@"ja", @"ko", @"zh-Hans", @"zh-Hant", @"cyrillic", @"central", @"el", @"tr"])
		if ([TSEncodingFamily(family) containsObject:@(preferred)])
			[families addObject:family];
	for (NSString *language in [NSLocale preferredLanguages])
		for (NSString *family in TSFamiliesForLanguage(language))
			if (! [families containsObject:family])
				[families addObject:family];
	[families addObject:@"western"];

	// Candidates: the preferred encoding, the encodings of those groups, then the rest of
	// TeXShop's list.
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
	BOOL (^available)(NSStringEncoding) = ^BOOL(NSStringEncoding encoding) { return [self isAvailableEncoding:encoding]; };

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
	if (lossy || (guess && ! (available(guess) && TSDataDecodes(data, guess))))
		guess = 0;

	// Among the Japanese encodings, choose the reading that looks most like Japanese.
	TSJapaneseScore japanese = {0, 0, 0, 0};
	NSStringEncoding bestJapanese = TSBestJapaneseEncoding(data, &japanese, available);
	if (guess && [TSEncodingFamily(@"ja") containsObject:@(guess)] && bestJapanese)
		guess = bestJapanese;
	// A one-byte guess, or none, gives way when the Japanese reading is clearly Japanese text:
	// it has kana, a positive score and hardly any half-width katakana, private use or
	// control characters.
	else if (bestJapanese && (! guess || TSIsSingleByteEncoding(guess)) && japanese.kana > 0
			&& japanese.score > 0 && 4 * japanese.unlikely <= japanese.japanese)
		guess = bestJapanese;

	// No guess at all, for a Japanese user: a Japanese reading that writes the file back
	// unchanged and looks like Japanese, even without kana, as in a single kanji.
	else if (bestJapanese && ! guess && [families containsObject:@"ja"] && japanese.score > 0
			&& japanese.unlikely == 0 && TSDataRoundTrips(data, bestJapanese))
		guess = bestJapanese;

	// A Chinese guess for a Japanese or Korean user who does not use Chinese: GB 18030 reads
	// almost any bytes, so a reading in the user's own encodings is preferred when one exists.
	if (guess && [TSEncodingVariants(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)) containsObject:@(guess)]
			&& ! [families containsObject:@"zh-Hans"] && ! [families containsObject:@"zh-Hant"]) {
		if ([families containsObject:@"ja"] && bestJapanese && TSDataRoundTrips(data, bestJapanese))
			guess = bestJapanese;
		else if ([families containsObject:@"ko"])
			for (NSNumber *korean in TSEncodingFamily(@"ko"))
				if (available(korean.unsignedIntegerValue) && TSDataRoundTrips(data, korean.unsignedIntegerValue)) {
					guess = korean.unsignedIntegerValue;
					break;
				}
	}

	// Among one-byte encodings, Foundation often confuses the Cyrillic and Central European
	// ones. Compare the readings in the encodings of the user's language groups, the preferred
	// encoding and the guess; on a tie the preferred encoding, then the guess wins.
	if (! guess || TSIsSingleByteEncoding(guess)) {
		NSMutableOrderedSet *oneByte = [NSMutableOrderedSet orderedSet];
		if (TSIsSingleByteEncoding(preferred))
			[oneByte addObject:@(preferred)];
		if (guess)
			[oneByte addObject:@(guess)];
		for (NSString *family in families)
			for (NSNumber *candidate in TSEncodingFamily(family))
				if (TSIsSingleByteEncoding(candidate.unsignedIntegerValue))
					[oneByte addObject:candidate];
		// Without a guess, the first candidate that reads the file stands in for one.
		if (! guess)
			for (NSNumber *candidate in oneByte)
				if (available(candidate.unsignedIntegerValue) && TSDataDecodes(data, candidate.unsignedIntegerValue)) {
					guess = candidate.unsignedIntegerValue;
					break;
				}
		// An ISO encoding whose reading has C1 control characters is usually the Windows
		// encoding of the same languages, which puts punctuation there.
		NSDictionary *windows = @{@(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin1)): @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin1)),
								  @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9)): @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin1)),
								  @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin2)): @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsLatin2))};
		if (guess && windows[@(guess)] && available([windows[@(guess)] unsignedIntegerValue])) {
			NSString *reading = [[NSString alloc] initWithData:data encoding:guess];
			NSString *windowsReading = [[NSString alloc] initWithData:data encoding:[windows[@(guess)] unsignedIntegerValue]];
			NSCharacterSet *c1 = [NSCharacterSet characterSetWithRange:NSMakeRange(0x80, 0x20)];
			if ([reading rangeOfCharacterFromSet:c1].location != NSNotFound && windowsReading
					&& [windowsReading rangeOfCharacterFromSet:c1].location == NSNotFound)
				guess = [windows[@(guess)] unsignedIntegerValue];
		}
		// A guess of the user's groups that reads as clean words is kept.
		TSAlphabeticScore guessReading = {0, 1};
		if (guess)
			guessReading = TSScoreAlphabetic([[NSString alloc] initWithData:data encoding:guess]);
		double bestScore = 0;
		NSStringEncoding best = 0;
		if (guess && guessReading.suspicious == 0 && [oneByte containsObject:@(guess)])
			[oneByte removeAllObjects];
		for (NSNumber *candidate in oneByte) {
			if (! available(candidate.unsignedIntegerValue))
				continue;
			NSString *text = [[NSString alloc] initWithData:data encoding:candidate.unsignedIntegerValue];
			if (! text)
				continue;
			double score = TSScoreAlphabetic(text).score;
			if (! best || score > bestScore) {
				best = candidate.unsignedIntegerValue;
				bestScore = score;
			}
		}
		if (best)
			guess = best;
		// The encoding that the file declares to inputenc is used unless its reading looks
		// clearly worse than the guess; declarations are sometimes wrong.
		NSStringEncoding declared = TSInputencEncoding(data);
		if (declared && guess && declared != guess && available(declared)) {
			NSString *declaredText = [[NSString alloc] initWithData:data encoding:declared];
			NSString *guessText = [[NSString alloc] initWithData:data encoding:guess];
			if (declaredText && guessText) {
				double declaredScore = TSScoreAlphabetic(declaredText).score, guessScore = TSScoreAlphabetic(guessText).score;
				if (declaredScore >= guessScore - MAX(2.0, 0.1 * fabs(guessScore)))
					guess = declared;
			}
		}
	}

	if (guess) {
		// GB 18030 includes GBK and GB 2312; use it whenever it writes the file back unchanged.
		NSStringEncoding gb18030 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
		if ([TSEncodingVariants(gb18030) containsObject:@(guess)] && guess != gb18030 && available(gb18030) && TSDataRoundTrips(data, gb18030))
			guess = gb18030;
		NSArray *variants = TSEncodingVariants(guess);
		// A variant of the guess that is the preferred encoding is kept, so that characters
		// typed later are written as the user's encoding expects.
		if (preferred != guess && [variants containsObject:@(preferred)] && TSDataRoundTrips(data, preferred))
			return preferred;
		// If the guess does not write the file back unchanged, a variant that does is used.
		if (! TSDataRoundTrips(data, guess))
			for (NSNumber *variant in variants)
				if (available(variant.unsignedIntegerValue) && TSDataRoundTrips(data, variant.unsignedIntegerValue))
					return variant.unsignedIntegerValue;
		return guess;
	}

	for (NSNumber *candidate in suggested)
		if (TSDataDecodes(data, candidate.unsignedIntegerValue))
			return candidate.unsignedIntegerValue;
	return preferred;
}

// UTF-8 in which each byte that does not start or continue a valid character is replaced
// by U+FFFD. validCharacters counts the characters of two or more bytes that were valid.
static NSString *TSLenientUTF8String(NSData *data, NSUInteger *validCharacters, NSUInteger *invalidBytes)
{
	const uint8_t *bytes = data.bytes;
	NSUInteger length = data.length, i = 0, segment = 0, valid = 0, invalid = 0;
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	while (i < length) {
		uint8_t c = bytes[i];
		if (c < 0x80) { i++; continue; }
		NSUInteger size = 0;
		uint32_t minimum = 0, code = 0;
		if (c >= 0xC2 && c <= 0xDF) { size = 2; minimum = 0x80; }
		else if (c >= 0xE0 && c <= 0xEF) { size = 3; minimum = 0x800; }
		else if (c >= 0xF0 && c <= 0xF4) { size = 4; minimum = 0x10000; }
		BOOL ok = size > 0 && i + size <= length;
		if (ok) {
			code = c & (0x7F >> size);
			for (NSUInteger k = 1; k < size && ok; k++) {
				if ((bytes[i + k] & 0xC0) != 0x80) ok = NO;
				else code = (code << 6) | (bytes[i + k] & 0x3F);
			}
			if (ok && (code < minimum || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)))
				ok = NO;
		}
		if (ok) {
			valid++;
			i += size;
			continue;
		}
		if (i > segment)
			[result appendString:[[NSString alloc] initWithBytes:bytes + segment length:i - segment encoding:NSUTF8StringEncoding] ?: @""];
		[result appendString:@"\uFFFD"];
		invalid++;
		segment = ++i;
	}
	if (length > segment)
		[result appendString:[[NSString alloc] initWithBytes:bytes + segment length:length - segment encoding:NSUTF8StringEncoding] ?: @""];
	if (validCharacters) *validCharacters = valid;
	if (invalidBytes) *invalidBytes = invalid;
	return result;
}

static BOOL TSBytesDecode(const uint8_t *bytes, NSUInteger length, NSStringEncoding encoding)
{
	return length == 0 || [[NSString alloc] initWithBytes:bytes length:length encoding:encoding] != nil;
}

// The number of bytes at the end of bytes that start a UTF-8 character without finishing it,
// and in *size the length of the whole character; 0 when the bytes do not end that way.
static NSUInteger TSUnfinishedUTF8Character(const uint8_t *bytes, NSUInteger length, NSUInteger *size)
{
	for (NSUInteger k = 1; k <= 3 && k <= length; k++) {
		uint8_t c = bytes[length - k];
		if ((c & 0xC0) == 0x80)
			continue;
		NSUInteger whole = (c >= 0xC2 && c <= 0xDF) ? 2 : (c >= 0xE0 && c <= 0xEF) ? 3 : (c >= 0xF0 && c <= 0xF4) ? 4 : 0;
		if (whole > k) {
			if (size) *size = whole;
			return k;
		}
		return 0;
	}
	return 0;
}

// The number of UTF-8 continuation bytes, at most limit, that start bytes.
static NSUInteger TSLeadingUTF8Continuations(const uint8_t *bytes, NSUInteger length, NSUInteger limit)
{
	NSUInteger n = 0;
	while (n < length && n < limit && (bytes[n] & 0xC0) == 0x80)
		n++;
	return n;
}

// TeX output and logs are read in UTF-8 for a UTF-16 document, since TeX does not write UTF-16.
static NSStringEncoding TSOutputEncoding(NSStringEncoding encoding)
{
	if (encoding == NSUnicodeStringEncoding || encoding == NSUTF16BigEndianStringEncoding || encoding == NSUTF16LittleEndianStringEncoding)
		return NSUTF8StringEncoding;
	return encoding;
}

// The first line break (LF, CRLF or CR) at or after from, or length if there is none;
// *breakLength is its length.
static NSUInteger TSNextLineBreak(const uint8_t *b, NSUInteger from, NSUInteger length, NSUInteger *breakLength)
{
	for (NSUInteger i = from; i < length; i++) {
		if (b[i] == '\n') { *breakLength = 1; return i; }
		if (b[i] == '\r') { *breakLength = (i + 1 < length && b[i + 1] == '\n') ? 2 : 1; return i; }
	}
	*breakLength = 0;
	return length;
}

// The start of the line that ends at end: just after the line break before end, or 0.
static NSUInteger TSLineStart(const uint8_t *b, NSUInteger end)
{
	while (end > 0 && b[end - 1] != '\n' && b[end - 1] != '\r')
		end--;
	return end;
}

// Whether the line from start to the line break at end, of breakLength bytes, looks like a
// UTF-8 line that TeX broke inside a character: it ends with the start of a character, and
// the rest of the line is UTF-8 unless the encoding is UTF-8 itself. *unfinished is the number
// of bytes of the character before the break, *needed the number after it, and *present the
// number of those that follow the break in bytes.
static BOOL TSLineBreakInsideCharacter(const uint8_t *b, NSUInteger start, NSUInteger end, NSUInteger breakLength, NSUInteger length,
									   NSStringEncoding encoding, NSUInteger *unfinished, NSUInteger *needed, NSUInteger *present)
{
	NSUInteger size = 0, k = TSUnfinishedUTF8Character(b + start, end - start, &size);
	if (k == 0)
		return NO;
	if (encoding != NSUTF8StringEncoding && ! TSBytesDecode(b + start, end - start - k, NSUTF8StringEncoding))
		return NO;
	*unfinished = k;
	*needed = size - k;
	*present = TSLeadingUTF8Continuations(b + end + breakLength, length - end - breakLength, size - k);
	return YES;
}

// One line of output. A line with bytes beyond ASCII is read in UTF-8, then in the encoding,
// then in UTF-8 with the bytes that are not UTF-8 replaced by U+FFFD when most of the line is
// UTF-8, and only otherwise in Latin 9. UTF-8 comes first because a UTF-8 line, such as a file
// name, often also reads as other characters in Shift JIS, while lines in the Japanese
// encodings almost never read as UTF-8. A line of ASCII is read in the encoding, which may
// give its escape sequences a meaning (ISO-2022-JP).
static NSString *TSDisplayStringForLine(const uint8_t *bytes, NSUInteger length, NSStringEncoding encoding)
{
	if (length == 0)
		return @"";
	BOOL ascii = YES;
	for (NSUInteger i = 0; i < length && ascii; i++)
		ascii = bytes[i] < 0x80;
	NSString *text = nil;
	if (ascii && (text = [[NSString alloc] initWithBytes:bytes length:length encoding:encoding]))
		return text;
	if ((text = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding]))
		return text;
	if (encoding != NSUTF8StringEncoding && (text = [[NSString alloc] initWithBytes:bytes length:length encoding:encoding]))
		return text;
	NSUInteger valid = 0, invalid = 0;
	text = TSLenientUTF8String([NSData dataWithBytesNoCopy:(void *)bytes length:length freeWhenDone:NO], &valid, &invalid);
	if (valid > 0 && valid >= invalid)
		return text;
	return [[NSString alloc] initWithBytes:bytes length:length encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9)] ?: @"";
}

// Output is read line by line, so that bytes in another encoding or broken bytes spoil only
// their own line, and a line reads the same however the output came in pieces. Output that is
// all UTF-8 in a UTF-8 document is read at once. TeX breaks long lines after a fixed number of
// bytes, which can put the line break inside a UTF-8 character; such a break is moved to just
// before the character, so that the character reads whole.
+ (NSString *)displayStringForData:(NSData *)data encoding:(NSStringEncoding)encoding
{
	encoding = TSOutputEncoding(encoding);
	NSString *text;
	if (encoding == NSUTF8StringEncoding && (text = [[NSString alloc] initWithData:data encoding:encoding]))
		return text;
	NSMutableData *bytes = [data mutableCopy];
	uint8_t *b = bytes.mutableBytes;
	NSUInteger length = bytes.length, start = 0;
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	while (start <= length) {
		NSUInteger breakLength = 0, end = TSNextLineBreak(b, start, length, &breakLength);
		NSUInteger unfinished = 0, needed = 0, present = 0;
		if (breakLength && TSLineBreakInsideCharacter(b, start, end, breakLength, length, encoding, &unfinished, &needed, &present) && present == needed) {
			uint8_t character[4];
			memcpy(character, b + end - unfinished, unfinished);
			memcpy(character + unfinished, b + end + breakLength, needed);
			if (TSBytesDecode(character, unfinished + needed, NSUTF8StringEncoding)) {
				// Move the line break from inside the character to before it.
				uint8_t lineBreak[2] = {b[end], breakLength > 1 ? b[end + 1] : 0};
				memmove(b + end - unfinished + breakLength, b + end - unfinished, unfinished);
				end -= unfinished;
				memcpy(b + end, lineBreak, breakLength);
			}
		}
		[result appendString:TSDisplayStringForLine(b + start, end - start, encoding)];
		if (! breakLength)
			break;
		[result appendString:(breakLength == 2 ? @"\r\n" : (b[end] == '\r' ? @"\r" : @"\n"))];
		start = end + breakLength;
	}
	return result;
}

// A line of output that has not ended is kept for the next piece when the encoding is not
// UTF-8 and the line has bytes beyond ASCII: in such an encoding a piece of a UTF-8 line can
// read as other characters, and the whole line decides how it is read. Longer lines are not kept.
static const NSUInteger TSLongestKeptLine = 4096;

// The number of bytes at the end of data to keep for the next piece of output: the start of a
// character, with a line break TeX put inside it, and when line is YES an unfinished line that
// is kept for its encoding to be decided.
static NSUInteger TSLengthToKeep(NSData *data, NSStringEncoding encoding, BOOL line)
{
	encoding = TSOutputEncoding(encoding);
	const uint8_t *b = data.bytes;
	NSUInteger length = data.length;
	if (length == 0)
		return 0;
	if (encoding == NSUTF8StringEncoding && TSBytesDecode(b, length, encoding))
		return 0;
	NSUInteger lineStart = TSLineStart(b, length);
	if (lineStart > 0) {
		NSUInteger breakLength = (b[lineStart - 1] == '\n' && lineStart >= 2 && b[lineStart - 2] == '\r') ? 2 : 1;
		NSUInteger previousEnd = lineStart - breakLength, previousStart = TSLineStart(b, previousEnd);
		NSUInteger unfinished = 0, needed = 0, present = 0;
		if (TSLineBreakInsideCharacter(b, previousStart, previousEnd, breakLength, length, encoding, &unfinished, &needed, &present)) {
			// A character TeX broke by a line break: until the rest of it has come, keep it
			// with the break, so that it can be joined with the rest in the next piece.
			if (present < needed && lineStart + present == length)
				return unfinished + breakLength + present;
			// Once it has all come, the character is joined when the output is shown.
			if (present == needed)
				lineStart += needed;
		}
	}
	if (line && encoding != NSUTF8StringEncoding && length - lineStart <= TSLongestKeptLine)
		for (NSUInteger i = lineStart; i < length; i++)
			if (b[i] >= 0x80)
				return length - lineStart;
	// The start of a UTF-8 character at the end of a line that is otherwise UTF-8. It is looked
	// for before the encoding, in which these bytes may read as other characters.
	NSUInteger unfinished = TSUnfinishedUTF8Character(b + lineStart, length - lineStart, NULL);
	if (unfinished && TSBytesDecode(b + lineStart, length - lineStart - unfinished, NSUTF8StringEncoding))
		return unfinished;
	// The start of a character at the end, in the encoding or in UTF-8: at most three bytes
	// are kept, which may be all of a short piece. A line that is UTF-8 is shown as UTF-8, so
	// none of it is kept, even where its bytes would begin a character in the encoding.
	if (TSBytesDecode(b + lineStart, length - lineStart, NSUTF8StringEncoding) || TSBytesDecode(b + lineStart, length - lineStart, encoding))
		return 0;
	for (NSUInteger k = 1; k <= 3 && k <= length - lineStart; k++)
		if (TSBytesDecode(b + lineStart, length - lineStart - k, encoding))
			return k;
	return unfinished;
}

+ (NSUInteger)lengthOfIncompleteCharacterAtEndOfData:(NSData *)data encoding:(NSStringEncoding)encoding
{
	return TSLengthToKeep(data, encoding, YES);
}

+ (NSUInteger)lengthOfUnfinishedCharacterAtEndOfData:(NSData *)data encoding:(NSStringEncoding)encoding
{
	return TSLengthToKeep(data, encoding, NO);
}

// A source file in encoding, for finding text in it: the encoding itself, then UTF-8, then UTF-8
// with the bytes that are not UTF-8 replaced by U+FFFD when most of it is UTF-8, and only
// otherwise Latin 9. Unlike output, the file is read whole in its encoding when it can be.
+ (NSString *)stringForSourceData:(NSData *)data encoding:(NSStringEncoding)encoding
{
	NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
	if (text)
		return text;
	if (encoding != NSUTF8StringEncoding && (text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]))
		return text;
	NSUInteger valid = 0, invalid = 0;
	text = TSLenientUTF8String(data, &valid, &invalid);
	if (valid > 0 && valid >= invalid)
		return text;
	return [[NSString alloc] initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9)] ?: @"";
}

// The byte order mark that starts data, so that a file can be saved with the same one.
+ (TSByteOrderMark)byteOrderMarkOfData:(NSData *)data
{
	const unsigned char *bytes = data.bytes;
	if (data.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
		return TSUTF8ByteOrderMark;
	if (data.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
		return TSUTF16BigEndianByteOrderMark;
	if (data.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
		return TSUTF16LittleEndianByteOrderMark;
	return TSNoByteOrderMark;
}

// Japanese encodings read the byte 0x5C, TeX's escape character, in two ways. Mac Japanese and
// Shift JIS X0213 read it as a yen sign and write a backslash as another byte (0x80, or the
// full-width backslash 81 5F); Shift JIS X0213 also reads 0x7E as an overline and writes a
// tilde as the wave dash 81 60. The other Japanese encodings read 0x5C as a backslash and
// cannot write a yen sign at all. A TeX source needs 0x5C and 0x7E whichever is typed.
static BOOL TSReadsBackslashAsYen(NSStringEncoding encoding)
{
	CFStringEncoding cf = CFStringConvertNSStringEncodingToEncoding(encoding);
	return cf == kCFStringEncodingMacJapanese || cf == kCFStringEncodingShiftJIS_X0213_00;
}

static BOOL TSReadsTildeAsOverline(NSStringEncoding encoding)
{
	return CFStringConvertNSStringEncodingToEncoding(encoding) == kCFStringEncodingShiftJIS_X0213_00;
}

static BOOL TSHasNoYenSign(NSStringEncoding encoding)
{
	CFStringEncoding cf = CFStringConvertNSStringEncodingToEncoding(encoding);
	return cf == kCFStringEncodingDOSJapanese || cf == kCFStringEncodingEUC_JP || cf == kCFStringEncodingISO_2022_JP;
}

static NSString *TSReplacing(NSString *text, NSString *from, NSString *to)
{
	return [text rangeOfString:from].location == NSNotFound ? text : [text stringByReplacingOccurrencesOfString:from withString:to];
}

// The text of a file read in encoding, as the editor shows it: TeX's escape character is a
// backslash, or a yen sign when typed backslashes become yen signs (Mac Japanese mode).
- (NSString *)textForEditing:(NSString *)text encoding:(NSStringEncoding)encoding
{
	if (TSReadsTildeAsOverline(encoding))
		text = TSReplacing(text, @"\u203E", @"~");
	if (TSReadsBackslashAsYen(encoding) && g_shouldFilter != kMacJapaneseFilterMode)
		text = TSReplacing(text, @"\u00A5", @"\\");
	else if (TSHasNoYenSign(encoding) && g_shouldFilter == kMacJapaneseFilterMode)
		text = TSReplacing(text, @"\\", @"\u00A5");
	return text;
}

// The text to write in encoding, so that backslashes, yen signs and tildes become 0x5C and 0x7E.
static NSString *TSTextForSaving(NSString *text, NSStringEncoding encoding)
{
	if (TSReadsBackslashAsYen(encoding))
		text = TSReplacing(text, @"\\", @"\u00A5");
	if (TSReadsTildeAsOverline(encoding))
		text = TSReplacing(text, @"~", @"\u203E");
	if (TSHasNoYenSign(encoding))
		text = TSReplacing(text, @"\u00A5", @"\\");
	return text;
}

- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(TSByteOrderMark)mark
{
	text = TSTextForSaving(text, encoding);
	if (encoding == NSUTF8StringEncoding && mark == TSUTF8ByteOrderMark) {
		NSMutableData *data = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
		[data appendData:[text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
		return data;
	}
	if (encoding == NSUnicodeStringEncoding && (mark == TSUTF16BigEndianByteOrderMark || mark == TSUTF16LittleEndianByteOrderMark)) {
		BOOL big = (mark == TSUTF16BigEndianByteOrderMark);
		NSMutableData *data = [NSMutableData dataWithBytes:(big ? "\xFE\xFF" : "\xFF\xFE") length:2];
		[data appendData:[text dataUsingEncoding:(big ? NSUTF16BigEndianStringEncoding : NSUTF16LittleEndianStringEncoding) allowLossyConversion:YES]];
		return data;
	}
	return [text dataUsingEncoding:encoding allowLossyConversion:YES];
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
    
	return [self dataForText:newString encoding:enc byteOrderMark:TSNoByteOrderMark];
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




