/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard Koch
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
 * $Id: TSDocumentController.m 260 2007-08-08 22:51:09Z richard_koch $
 *
 * Created by Richard Koch on Sun Feb 16 2003.
 * Parts of this code are taken from Apple's example SimpleToolbar
 *
 */


#import "TSDocumentController.h"
#import "TSEncodingSupport.h"
#import "TSDocument.h"

@implementation TSDocumentController : NSDocumentController

- (id)init
{
    id result = [super init];
	doList = YES;
    return result;
}


- (void)initializeEncoding  // the idea is that this is called after preferences is set up
{
	// We use the _encoding field to store the encoding to be used for the
	// next openend file. Normally, this is just the default encoding, and
	// we use that as the initial value of _encoding. However, in the open
	// dialog, the user can choose a custom encoding; if that happens, then
	// the value of _encoding is modified (see runModalOpenPanel below).
	// This happens before openDocument: is called.
	_encoding = [[TSEncodingSupport sharedInstance] defaultEncoding];
}

- (NSStringEncoding)encoding
{
    	return _encoding;
}

- (NSString *)defaultType
{
 //   return @"org.tug.tex";
    return @"edu.uo.texshop.tex";
}

- (IBAction)newDocument:(id)sender
{
	_encoding = [[TSEncodingSupport sharedInstance] defaultEncoding];
	[super newDocument: sender];
}



- (IBAction)newDocumentFromStationery: (id)sender
{
	
}

- (IBAction)openDocument:(id)sender
{
	[super openDocument: sender];
	// _encoding = [[TSEncodingSupport sharedInstance] defaultEncoding]; Terada Yusuke says to comment it out
}


- (NSInteger)runModalOpenPanel:(NSOpenPanel *)openPanel forTypes:(NSArray *)extensions
{
	NSInteger					result;

	// Set an accessory view, with the encoding popup button in it.
	[openPanel setAccessoryView: encodingView];
//	[encodingView retain];	// FIXME: Is this line really necessary?

	// Create the contents of the encoding menu on the fly & select the active encoding
	[encodingMenu removeAllItems];
	[[TSEncodingSupport sharedInstance] addEncodingsToMenu:[encodingMenu menu] withTarget:0 action:0];
	[encodingMenu selectItemWithTag: [[TSEncodingSupport sharedInstance] defaultEncoding]];

	_chosenEncodingURLs = nil;
	result = [super runModalOpenPanel: openPanel forTypes: extensions];
	if (result == YES) {
		_encoding = [[encodingMenu selectedCell] tag];
		// An encoding other than the default is the user's choice for these files;
		// with the default, the encoding of each file is detected.
		_chosenEncoding = _encoding;
		_chosenEncodingURLs = nil;
		if (_encoding != [[TSEncodingSupport sharedInstance] defaultEncoding]) {
			_chosenEncodingURLs = [NSMutableSet set];
			for (NSURL *url in openPanel.URLs)
				[_chosenEncodingURLs addObject: url.URLByStandardizingPath];
		}
	}
	return result;
}

// An encoding chosen in the Open panel is for the opening it was chosen for. When the file is
// already open, or the opening fails, it is not read; the choice must not be left for a later
// reading of the file, such as a reload after an external change. Every way of opening asks
// documentForURL: for an open document first; the completion handler covers failures.
- (NSDocument *)documentForURL:(NSURL *)url
{
	NSDocument *document = [super documentForURL: url];
	NSURL *key = url.URLByStandardizingPath;
	if (document && key)
		[_chosenEncodingURLs removeObject: key];
	return document;
}

- (void)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)displayDocument completionHandler:(void (^)(NSDocument *, BOOL, NSError *))completionHandler
{
	NSURL *key = url.URLByStandardizingPath;
	[super openDocumentWithContentsOfURL: url display: displayDocument completionHandler: ^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
		if (key)
			[self->_chosenEncodingURLs removeObject: key];
		if (completionHandler)
			completionHandler(document, documentWasAlreadyOpen, error);
	}];
}

- (BOOL)takeEncoding:(NSStringEncoding *)encoding chosenForURL:(NSURL *)url
{
	NSURL *key = url.URLByStandardizingPath;
	if (! key || ! [_chosenEncodingURLs containsObject: key])
		return NO;
	[_chosenEncodingURLs removeObject: key];
	*encoding = _chosenEncoding;
	return YES;
}

- (void)noteNewRecentDocument:(NSDocument *)aDocument
{
	if (doList)
		[super noteNewRecentDocument:aDocument];
}

- (void)listDocument:(BOOL)value;
{
	doList = value;
}



/* The code below was an attempt to support the "Stationery Bit", but I don't know how to find its
 value in Cocoa. NSFileImmutable isn't it.
 
 

- (id)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)outError
{
	
	NSString *path = [absoluteURL path];
	if (path) {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSDictionary *values = [fileManager attributesOfItemAtPath: path error: NULL];
		NSNumber *theResult = [values valueForKey: @"NSFileImmutable"];
		if ([theResult boolValue])
			NSLog(@"it is stationery");
		NSLog([theResult stringValue]);
	}
	
	return [super openDocumentWithContentsOfURL:absoluteURL display:displayDocument error:outError];
}
*/

/*

- (void)closeAllDocumentsWithDelegate:(id)delegate didCloseAllSelector:(SEL)didCloseAllSelector contextInfo:(void *)contextInfo
{
    NSLog(@"documents should terminate");
    
    NSArray *myDocuments = [self documents];
    NSInteger i;
    id obj;
    i = 1;
    while (i < [myDocuments count]) {
        obj = [myDocuments objectAtIndex: (i - 1)];
        i++;
        if ([(TSDocument *)obj skipTextWindow])
            [(TSDocument *)obj close];
    }
    [super closeAllDocumentsWithDelegate:delegate didCloseAllSelector:didCloseAllSelector contextInfo: contextInfo];

}
*/

@end
