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
 * $Id: TSDocument-RootFile.m 260 2007-08-08 22:51:09Z richard_koch $
 *
 */

#import "UseMitsu.h"

#import "TSDocument.h"
#import "globals.h"
#import "TSEncodingSupport.h"
#import "TSAppDelegate.h"
#import "TSTextEditorWindow.h"
#import "NSString-Extras.h"
#import "TSRootFileResolver.h"

@implementation TSDocument (RootFile)

/*
- (id) rootDocument
{
	return rootDocument;
}
*/

- (BOOL) checkRootFile: (NSString *)nameString forTask:(NSInteger)task
{
	NSArray 			*wlist;
	NSEnumerator 		*en;
	id                      obj;
	NSDocumentController    *dc;
	NSInteger                         theEngine;

	// is the document open?
	wlist = [NSApp orderedDocuments];
	en = [wlist objectEnumerator];
	while ((obj = [en nextObject])) {
		// TODO: Consider using [obj isMemberOfClass:[TSDocument class]] here
		if ([[obj windowNibName] isEqualToString:@"TSDocument"]) {
            BOOL isRootFileWindow = [SUD boolForKey:AutomaticUTF8MACtoUTF8ConversionKey] ?
                                        [[[[obj fileURL] path] normalizedStringWithModifiedNFC] isEqualToString:[nameString normalizedStringWithModifiedNFC]] :
                                        [[[obj fileURL] path] isEqualToString:nameString];

            BOOL usingFullSplitWindow = NO;
            if (isRootFileWindow){
                id theTextWindow = [(TSDocument*)obj textWindow];
                if ([theTextWindow isMemberOfClass:[TSTextEditorWindow class]]) {
                    TSTextEditorWindow* theTextEditorWindow = (TSTextEditorWindow*)theTextWindow;
                    if ([theTextEditorWindow wasClosed]) {
                        isRootFileWindow = NO;
                    } else if ([(TSDocument*)obj useFullSplitWindow]) {
                        usingFullSplitWindow = YES;
                    }
                }
            }
            
            if (isRootFileWindow) {
				if (obj == self)
					return NO;
				self.rootDocument = obj;
				if (task == RootForConsole){
					[obj displayConsole:nil];
				} else if (task == RootForLogFile){
					[obj displayLog:nil];
                } else if (task == RootForRedisplayLog){
					[obj reDisplayLog];
   				} else if (task == RootForPrinting) {
					[obj printDocument:nil];
				} else if (task == RootForPdfSync) {
					[obj doPreviewSyncWithFilename:[[self fileURL] path] andLine:pdfSyncLine andCharacterIndex:pdfCharacterIndex andTextView: textView];
				} else if (task == RootForSwitchWindow) {
					[obj setCallingWindow: textWindow];
                    if (usingFullSplitWindow) {
                        [[(TSDocument*)obj fullSplitWindow] makeKeyAndOrderFront:nil];
                    } else {
                        [obj bringPdfWindowFront];
                    }
				} else if (task == RootForTexing) {
					// Command-1 in the root preview returns to the file typeset from.
					[obj setCallingWindow: textWindow];
					// FIXME: The following code block exists twice in this function
  
					theEngine = useTempEngine ? tempEngine : whichEngine;
					if (whichEngine >= UserEngine) {
						[obj doUser:whichEngine];
					} else {
						switch (theEngine) {
							case TexEngine: [obj doTex1:nil]; break;
							case LatexEngine: [obj doLatex1:nil]; break;
							// case ContextEngine: [obj doContext1:nil]; break;
							case MetapostEngine: [obj doMetapost1:nil]; break;
							case BibtexEngine: [obj doBibtex:nil]; break;
							case IndexEngine: [obj doIndex:nil]; break;
							default: NSBeginAlertSheet(NSLocalizedString(@"Typesetting engine cannot be found.", @"Typesetting engine cannot be found."),
													   nil,nil,nil,[textView window],nil,nil,nil,nil,
													   @"Path Name: %@",nameString);
						}
					}
				} else if (task == RootForOpening) {
					/* This section was moved lower down for version 2.40
					 
					// added by Terada (from this line)
					NSRect activeWindowFrame = [[obj textWindow] frame];
					NSRect newFrame;
					NSScreen *screen = [NSScreen mainScreen];
					if(NSMinY(activeWindowFrame) + NSHeight([screen visibleFrame]) - NSHeight([screen frame]) + 20 < 0)
					{
						newFrame = NSMakeRect(NSMinX(activeWindowFrame) + 20, NSHeight([screen frame]), NSWidth(activeWindowFrame), NSHeight(activeWindowFrame));
					}
					else
					{
						newFrame = NSMakeRect(NSMinX(activeWindowFrame) + 20, NSMinY(activeWindowFrame) + 20, NSWidth(activeWindowFrame), NSHeight(activeWindowFrame));
					}
					
					[[obj textWindow] setFrame:newFrame display:YES];
					// added by Terada (until this line)
					*/
				} else if (task == RootForTrashAUX) {
					[obj trashAUXWithAggressiveness:aggressiveTrash];
				}
				return YES;
			}
		}
	}

	// document not found, open document and typeset
	dc = [NSDocumentController sharedDocumentController];
	//	obj = [dc openDocumentWithContentsOfURL:[NSURL fileURLWithPath: nameString] display:YES error:NULL];
	obj = [[NSFileManager defaultManager] fileExistsAtPath:nameString] ? [dc openDocumentWithContentsOfURL:[NSURL fileURLWithPath: nameString] 
                                                                        display:YES error:NULL] : nil; // modified by Terada
	if (obj) {
		if (obj == self)
			return NO;
		if (task == RootForPrinting) {
            
            if([SUD boolForKey:MiniaturizeRootFileKey])
                [[obj textWindow] performSelector:@selector(miniaturize:) withObject:self afterDelay:0];
			[obj printDocument:nil];
		} else if (task == RootForPdfSync) {
            if([SUD boolForKey:MiniaturizeRootFileKey])
                [[obj textWindow] performSelector:@selector(miniaturize:) withObject:self afterDelay:0];
			[obj doPreviewSyncWithFilename:[[self fileURL] path] andLine:pdfSyncLine andCharacterIndex:pdfCharacterIndex andTextView: textView];
		} else if (task == RootForTexing) {
			[obj setCallingWindow: textWindow];
            if([SUD boolForKey:MiniaturizeRootFileKey])
                [[obj textWindow] performSelector:@selector(miniaturize:) withObject:self afterDelay:0];
			// FIXME: The following code block exists twice in this function

/*
			[obj printDocument:nil];
		} else if (task == RootForPdfSync) {
			[obj doPreviewSyncWithFilename:[[self fileURL] path] andLine:pdfSyncLine andCharacterIndex:pdfCharacterIndex andTextView: textView];
		} else if (task == RootForTexing) {
			// FIXME: The following code block exists twice in this function
*/
			theEngine = useTempEngine ? tempEngine : whichEngine;
			if (whichEngine >= UserEngine) {
				[obj doUser:whichEngine];
			} else {
				switch (theEngine) {
					case TexEngine: [obj doTex1:nil]; break;
					case LatexEngine: [obj doLatex1:nil]; break;
					// case ContextEngine: [obj doContext1:nil]; break;
					case MetapostEngine: [obj doMetapost1:nil]; break;
					case BibtexEngine: [obj doBibtex:nil]; break;
					case IndexEngine: [obj doIndex:nil]; break;
					default: NSBeginAlertSheet(NSLocalizedString(@"Typesetting engine cannot be found.", @"Typesetting engine cannot be found."),
											   nil,nil,nil,[textView window],nil,nil,nil,nil,
											   @"Path Name: %@",nameString);
				}
			}
		} else if (task == RootForOpening) {
			// added by Terada (from this line) // This was moved here for version 2.40
			/*
             if([SUD integerForKey:DocumentWindowPosModeKey] == DocumentWindowPosSave){
				NSRect activeWindowFrame = [[obj textWindow] frame];
				NSScreen *screen = [NSScreen mainScreen];
				CGFloat minX = 20 + ((NSMinX(activeWindowFrame) + NSWidth(activeWindowFrame) + 20 > NSWidth([screen frame])) ? 0 : NSMinX(activeWindowFrame));
				CGFloat minY = (NSMinY(activeWindowFrame) + NSHeight([screen visibleFrame]) - NSHeight([screen frame]) + 20 < 0) ? NSHeight([screen frame]) : NSMinY(activeWindowFrame) - 20;
				NSRect newFrame = NSMakeRect(minX, minY, NSWidth(activeWindowFrame), NSHeight(activeWindowFrame));
				[[obj textWindow] setFrame:newFrame display:YES];
			}
             */
            
            if([SUD boolForKey:MiniaturizeRootFileKey])
                [[obj textWindow] performSelector:@selector(miniaturize:) withObject:self afterDelay:0];
            else
                [(TSAppDelegate*)[NSApp delegate] performSelector:@selector(nextTeXWindow:) withObject:nil afterDelay:0];
            // added by Terada (until this line)
        } else if (task == RootForSwitchWindow) {
            if([SUD boolForKey:MiniaturizeRootFileKey])
                [[obj textWindow] performSelector:@selector(miniaturize:) withObject:self afterDelay:0];
            [obj setCallingWindow: textWindow];
            [obj bringPdfWindowFront];
        } else if (task == RootForTrashAUX) {
			[obj trashAUXWithAggressiveness:aggressiveTrash];
		}
		return YES;
	} else {
		[self reportMissingRootFile: nameString forTask: task];
	}
        return YES;
}

// The root file named by "% !TEX root =" does not exist. NSUserNotification is no
// longer displayed on current macOS, so tell the user with a sheet on the document
// window instead; otherwise typesetting silently does nothing. Opening a document
// whose root file is missing stays quiet.
- (void)reportMissingRootFile: (NSString *)nameString forTask:(NSInteger)task
{
	if (task == RootForOpening)
		return;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = NSLocalizedString(@"The source LaTeX document cannot be found.", @"The source LaTeX document cannot be found.");
	alert.informativeText = nameString ?: @"";
	NSWindow *window = [self windowForSheet];
	if (window && !window.attachedSheet)
		[alert beginSheetModalForWindow: window completionHandler: nil];
	else
		[alert runModal];
}

/*
			// added by Terada (until this line)
			[[obj textWindow] miniaturize:self];
		} else if (task == RootForTrashAUX) {
			[obj trashAUXWithAggressiveness:aggressiveTrash];
		}
		return YES;
	} else {
		NSBeginAlertSheet(NSLocalizedString(@"The source LaTeX document cannot be found.", @"The source LaTeX document cannot be found."),
						  nil,nil,nil,nil,nil,nil,nil,nil,
						  @"Path Name: %@",nameString);
	}
	return YES;
}
*/

- (BOOL)checkMasterFile:(NSString *)theSource forTask:(NSInteger)task
{
	NSString                *home, *jobname;
	NSString                *nameString;
	TSRootFileSpecifier     *specifier;

	if (theSource == nil)
		return NO;

	// load home path and jobname
	home = [[[self fileURL] path] stringByDeletingLastPathComponent];
	jobname = [[[[self fileURL] path] lastPathComponent] stringByDeletingPathExtension];

	// see if there is a parent document: "% !TEX root =" in the first 20 lines, or the old "%SourceDoc "
	specifier = [TSRootFileResolver specifierInSource:theSource
	                                allowingSourceDoc:[SUD boolForKey:UseOldHeadingCommandsKey]];

	// A typeset or Command-1 given in this window makes it the calling window
	// again, replacing a window of another file that typeset this one as root.
	if (self.directRootCommand && ((task == RootForSwitchWindow) || (task == RootForTexing)))
		[self setCallingWindow: textWindow];
	self.directRootCommand = NO;

    if(task == RootForOpening && ![SUD boolForKey:AutoOpenRootFileKey])
        return NO;


	if (specifier) {

		nameString = [self
			decodeFile:specifier.value
			  homePath:home job:jobname];

		return [self checkRootFile:nameString forTask:task];
	}

	return NO;
}


- (BOOL) checkRootFile_forTask:(NSInteger)task
{
	NSString			*projectPath, *nameString;
    NSStringEncoding    theEncoding;
    
  	projectPath = [[[[self fileURL] path] stringByDeletingPathExtension] stringByAppendingPathExtension:@"texshop"];
	if (![[NSFileManager defaultManager] fileExistsAtPath: projectPath])
		return NO;

	NSString *projectRoot = [NSString stringWithContentsOfFile: projectPath usedEncoding: &theEncoding error:NULL]
		?: [NSString stringWithContentsOfFile: projectPath encoding: NSISOLatin1StringEncoding error: NULL]; // written in Latin 1 before
	projectRoot = [projectRoot stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([projectRoot length] == 0)
		return NO;
    
	if ([projectRoot isAbsolutePath]) {
		nameString = [NSString stringWithString:projectRoot];
	} else {
		nameString = [[[self fileURL] path] stringByDeletingLastPathComponent];
		nameString = [[nameString stringByAppendingString:@"/"]
                      stringByAppendingString: projectRoot];
		nameString = [nameString stringByStandardizingPath];
	}

	return [self checkRootFile:nameString forTask:task];
}

/* Removed by Ulrich Bauer patch */

- (void) checkFileLinksA
{
	NSArray *wlist;
	NSEnumerator *en;
	id obj;
	id theRoot;

	// first save all related, open, dirty files
	theRoot = self.rootDocument ? self.rootDocument : self;

	wlist = [NSApp orderedDocuments];
	en = [wlist objectEnumerator];
	while ((obj = [en nextObject])) {

		if (([[obj windowNibName] isEqualToString:@"TSDocument"]) &&
			(obj != self) &&
			(([obj rootDocument] == theRoot) || (obj == self.rootDocument)) &&
			([obj isDocumentEdited])) {
			[obj saveDocument:self];
		}
	}
}

 
// End Bauer

// added by John A. Nairn
// get full path name for possible relative file name in relFile
// relative is from home
- (NSString *) decodeFile:(NSString *)relFile homePath:(NSString *)home job:(NSString *)jobname
{
	return [TSRootFileResolver pathForName:relFile homePath:home jobName:jobname
	                          jobNameToken:[self filterBackslashes:@"\\jobname"]];
}


@end
