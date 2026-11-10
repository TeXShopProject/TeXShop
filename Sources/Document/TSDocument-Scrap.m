/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2014 Richard Koch
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
 * $Id: TSDocument-Jobs.m 254 2014-06-28 21:09:25Z fingolfin $
 *
 */

#import "UseMitsu.h"

#import "TSDocument.h"
#import "TSExperimentConsoleController.h"
#import "TSTextView.h"

#import "MyPDFView.h"
#import "MyPDFKitView.h"

#import "globals.h"

#import "TSWindowManager.h"
#import "TSEncodingSupport.h"
#import "NSText-Extras.h"



@implementation TSDocument (Scrap)

- (void)windowWillClose:(NSNotification *)notification
{
    if ([notification object] == scrapWindow)
    {
        [self closeExperiment];
    }
}


- (BOOL)experimentHasKeyWindow
{
    return scrapWindow.isKeyWindow || scrapPDFWindow.isKeyWindow ||
        (self.experimentConsole.isWindowLoaded && self.experimentConsole.window.isKeyWindow);
}

- (TSExperimentConsoleController *)ensureExperimentConsole
{
    if (!self.experimentConsole) {
        self.experimentConsole = [[TSExperimentConsoleController alloc] init];
        __weak TSDocument *weakSelf = self;
        self.experimentConsole.typesetHandler = ^{ [weakSelf typesetScrap:nil]; };
        self.experimentConsole.returnHandler = ^{ [weakSelf activateExperimentWindow]; };
    }
    return self.experimentConsole;
}

- (void)showExperimentConsole
{
    [[self ensureExperimentConsole] toggleFromWindow:NSApp.keyWindow];
}

- (void)closeExperiment
{
    [self.experimentConsole invalidate];
    self.experimentConsole = nil;
    [scrapPDFWindow close];
    [scrapPDFKitView setDocument:nil];
}

- (NSString *)getFilePath
{
    NSDocument  *theDocument;
    NSURL       *sourceURL;
    
    if (self.rootDocument != nil)
        theDocument = self.rootDocument;
    else
        theDocument = self;
    sourceURL = theDocument.fileURL;
    if (sourceURL == nil)
        return nil;
    else
        return [sourceURL path];
}

- (void) tryScrap:(id)sender
{
    BOOL        spellExists;
    NSString    *newTitle;
    
    if ([self getFilePath] == nil)
        return;
    
    NSString *selectedStuff;
    NSArray *ranges = [textView selectedRanges];
    if ([ranges count] > 0)
    {
        selectedStuff = [[textView string] substringWithRange: [ranges[0] rangeValue]];
        if ([selectedStuff length] > 0)
            scrapTextView.string = selectedStuff;
    }
    
    
    scrapTextView.document = self;
    [scrapTextView setAllowsUndo: YES];
    [scrapTextView setRichText: NO];
    [scrapTextView setAutomaticQuoteSubstitutionEnabled:NO];
    [scrapTextView setAutomaticLinkDetectionEnabled:NO];
    [scrapTextView setAutomaticDashSubstitutionEnabled:NO];
    [scrapTextView setUsesRuler:NO];
 
    NS_DURING
    NSSpellChecker *myChecker = [NSSpellChecker sharedSpellChecker];
    spellExists = (myChecker != 0);
	NS_HANDLER
    spellExists = NO;
	NS_ENDHANDLER
    if (spellExists) {
		[scrapTextView setContinuousSpellCheckingEnabled:[SUD boolForKey:SpellCheckEnabledKey]];
        [scrapTextView setAutomaticSpellingCorrectionEnabled:[SUD boolForKey:AutomaticSpellingCorrectionEnabledKey]];
        }
    
    if ([SUD boolForKey:SaveDocumentFontKey] == YES)
        {
        NSData	*fontData;
        NSFont 	*font;
        
        fontData = [SUD objectForKey:DocumentFontKey];
        if (fontData != nil)
            {
            font = [NSUnarchiver unarchiveObjectWithData:fontData];
            [scrapTextView setFontSafely:font];
            }
        }

    if ([textWindow title])
        newTitle = [[textWindow title] stringByDeletingPathExtension];
    else
        newTitle = @"Experiment";
    [scrapWindow setTitle: newTitle];
    [scrapPDFWindow setTitle: newTitle];
    [scrapWindow setHidesOnDeactivate:YES];
    [scrapWindow makeKeyAndOrderFront:sender];
}


- (IBAction) typesetScrap:(id)sender
{
    NSString            *theSource, *theHeader, *newSource;
    NSRange             beginDoc;
    NSData              *theData;
    NSError             *error;
    NSString            *filePath, *fileLocation;
    TSDocument          *theDocument;
    NSStringEncoding    encoding;

    filePath = [self getFilePath];
    if (filePath == nil)
        return;
    fileLocation = [filePath stringByDeletingLastPathComponent];
    
    if (self.rootDocument != nil)
        theDocument = self.rootDocument;
    else
        theDocument = self;
    self.scrapMenuEngine = [[theDocument programButton] titleOfSelectedItem];
    self.scrapDVI = [theDocument useDVI];
    self.scrapScript = theDocument->whichScript;
    
    theSource = [[theDocument textView] string];
    
     
    beginDoc = [theSource rangeOfString: @"\\begin{document}"];
    
    if (beginDoc.location == NSNotFound)
  //      return;
        theHeader = theSource;
    else
    {
        theHeader = [theSource substringToIndex:beginDoc.location];
    }
    newSource = [theHeader stringByAppendingString:@"\n\\begin{document}\n"];
    newSource = [newSource stringByAppendingString: [scrapTextView string]];
    newSource = [newSource stringByAppendingString:@"\n\\end{document}\n"];
 
    // get encoding and use it to write the file
    [self searchFile: newSource];
    if (self.scrapEncoding != nil)
        encoding = [[TSEncodingSupport sharedInstance] stringEncodingForKey: self.scrapEncoding];
    else
        encoding = [theDocument encoding];
    if (encoding == NSUnicodeStringEncoding) encoding = NSUTF8StringEncoding;
    self.scrapEffectiveEncoding = encoding;
    theData = [[TSEncodingSupport sharedInstance] dataForText:newSource encoding:encoding byteOrderMark:TSNoByteOrderMark];
    if (!theData) { NSBeep(); return; }
    
 
// The following code comes from http://nshipster.com/nstemporarydirectory/
    
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self presentError:error];
        return;
    }
    NSURL *fileURL = [directory URLByAppendingPathComponent:@"file.tex"];
    if (![theData writeToURL:fileURL options:NSDataWritingAtomic error:&error]) {
        [[NSFileManager defaultManager] removeItemAtURL:directory error:NULL];
        [self presentError:error];
        return;
    }

    [self typesetFile: fileURL withAdditionalPath:fileLocation];
    
}

- (NSDictionary *)environmentWithNewPath: (NSString *)additionalPath;
{
	NSMutableDictionary *env;
    
    
	// get copy of environment and add the preferences paths
	env = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
    
    
	// Customize 'PATH'
    NSMutableString *inputs;
    NSMutableString *path;
    NSString *extraPath;
	path = [NSMutableString stringWithString: ([env objectForKey:@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin")];
	extraPath = [[SUD stringForKey:TetexBinPath] stringByExpandingTildeInPath];
	if ([extraPath length] > 0) {
		[path appendString:@":"];
		[path appendString:extraPath];
	}
	extraPath = [SUD stringForKey:GSBinPath];
	if ([extraPath length] > 0) {
		[path appendString:@":"];
		[path appendString:extraPath];
	}
    [path appendString:@":"];
    [path appendString:additionalPath];
	[env setObject: path forKey: @"PATH"];
    inputs = [NSMutableString stringWithString: @".:"];
    [inputs appendString:additionalPath];
    [inputs appendString:@":"];
    [env setObject: inputs forKey: @"TEXINPUTS"];
    
    
 /*
	// Set 'TEXEDIT' env var (see the 'tex' man page for details). We construct a simple shell
	// command, which first (re)opens the document, and then uses osascript to run an AppleScript
	// which selects the right line. The AppleScript looks like this:
	//   tell application "TeXShop"
	//       goto document 1 line %d
	//       activate
	//   end tell
	NSMutableString *script = [NSMutableString string];
    
	[script appendFormat:@"open -a '%@' '%%s' &&", [[NSBundle mainBundle] bundlePath]];
	[script appendString:@" osascript"];
	[script appendString:@" -e 'tell application \"TeXShop\"'"];
	[script appendString:@" -e     'goto document 1 line %d'"];
	[script appendString:@" -e     'activate'"];
	[script appendString:@" -e 'end tell'"];
    
	[env setObject: script forKey:@"TEXEDIT"];
*/
	
    
    
	return env;
}

- (void)searchFile: (NSString *)theSource
{
    NSUInteger  length, start, end, irrelevant, offset;
    BOOL        programDone, encodingDone;
    NSRange     myRange, theRange;
    NSRange     programRange, encodingRange, newProgramRange, newEncodingRange;
    NSUInteger  linesTested;
    NSString    *testString;
    
    self.scrapEncoding = nil;
    self.scrapProgram = nil;
    
     
    length = [theSource length];
    programDone = NO; encodingDone = NO;
    linesTested = 0;
    myRange.location = 0;
    myRange.length = 1;
   
    while ((myRange.location < length) && (linesTested < 20) && ((! programDone) || (! encodingDone))) {
        
        [theSource getLineStart: &start end: &end contentsEnd: &irrelevant forRange: myRange];
        myRange.location = end;
        myRange.length = 1;
        linesTested++;
        
        theRange.location = start; theRange.length = (end - start);
        testString = [theSource substringWithRange: theRange];
        
        if (! programDone) {
            
            programRange = [testString rangeOfString:@"%!TEX TS-program ="];
            offset = 18;
            if (programRange.location == NSNotFound) {
                programRange = [testString rangeOfString:@"% !TEX TS-program ="];
                offset = 19;
			}
            if (programRange.location == NSNotFound) {
                programRange = [testString rangeOfString:@"% !TEX program ="];
                offset = 16;
            }
            if (programRange.location == NSNotFound) {
                programRange = [testString rangeOfString:@"%!TEX program ="];
                offset = 15;
            }
           
            if (programRange.location != NSNotFound) {
                newProgramRange.location = programRange.location + offset;
                newProgramRange.length = [testString length] - newProgramRange.location;
                if (newProgramRange.length > 0) {
                    self.scrapProgram = [[[testString substringWithRange: newProgramRange]
                                          stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
                    programDone = YES;
                    }
                }
            }
        
        if (! encodingDone) {
            
            encodingRange = [testString rangeOfString:@"%!TEX encoding ="];
            offset = 16;
            if (encodingRange.location == NSNotFound) {
                encodingRange = [testString rangeOfString:@"% !TEX encoding ="];
                offset = 17;
			}
            
            if (encodingRange.location != NSNotFound) {
             //   NSLog(@"also got here");
                newEncodingRange.location = encodingRange.location + offset;
                newEncodingRange.length = [testString length] - newEncodingRange.location;
                if (newEncodingRange.length > 0) {
                    self.scrapEncoding = [[testString substringWithRange: newEncodingRange]
                                     stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    // encodingString = [programString lowercaseString];
                    encodingDone = YES;
                }
            }
        }
    }
	
    
    
    
}

- (NSString*)absoluteEnginePath:(NSString*)enginePath
{
    NSString *absolutePath = [enginePath stringByExpandingTildeInPath];
    
    if(![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:nil]){
        absolutePath = [[[SUD stringForKey:TetexBinPath] stringByExpandingTildeInPath] stringByAppendingPathComponent:enginePath];
    }
    
    return absolutePath;
}






- (void)typesetFile: (NSURL *)fileURL withAdditionalPath: (NSString *)additionalPath
{
    
    NSString        *sourcePath;
    NSMutableArray  *args;
    NSString        *enginePath;
    NSDictionary    *env;
    NSString        *userEngine;
    NSString        *tempPath;
    NSString        *theProgramWithFlags;
    
    
    env = [self environmentWithNewPath: additionalPath];
    
    sourcePath = [fileURL path];
    
    
    args = [NSMutableArray array];
    
    // Note: the NSDocument variable whichScript is set to 100 for pdflatex, 101 for tex + dvi and 102 for personal script
    // Note: scrapMenuEngine is the engine in the pulldown menu next to Typeset in the source toolbar
    // Note; scrapProgram is the program set via "% !TeXShop program = "
    // Note: Therefore if scrapMenuEngine is active and "latex", then whichScript should set the typeset job to
    //       pdflatex, latex, or personallatex depending on whichScript
    
    // get program and use it to typeset the file
    // first get program selected in pulldown menu
    if (self.scrapProgram == nil)
        {
        userEngine = [[self.scrapMenuEngine stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if ([userEngine isEqualToString: @"latex"])
            {
            if (self.scrapScript == 102)
                userEngine = @"personallatex";
            else if (self.scrapScript == 101)
                userEngine = @"latex";
            else
                userEngine = @"pdflatex";
            }
        }
     else
        userEngine = self.scrapProgram;
            
         
    if ([@[@"plaintex", @"tex", @"metapost", @"personaltex"] containsObject:userEngine ?: @""]) {
        [[NSFileManager defaultManager] removeItemAtURL:[fileURL URLByDeletingLastPathComponent] error:NULL];
        NSBeep();
        return;
    }
    if ([userEngine isEqualToString:@"bibtex"] || [userEngine isEqualToString:@"makeindex"])
        userEngine = @"pdflatex";

//  Fixed to use settings in Preferences RMK
    
//  LatexScriptCommandKey
    
    if ([userEngine isEqualToString:@"personallatex"]) {
      //  NSLog(@"got here");
        theProgramWithFlags = [[SUD stringForKey: LatexScriptCommandKey] stringByExpandingTildeInPath];
        enginePath = [self separate:theProgramWithFlags into:args];
        // [args addObject: [sourcePath lastPathComponent]];
        // tetexBinPath = [[[SUD stringForKey:TetexBinPath] stringByExpandingTildeInPath] stringByAppendingString:@"/"];
        // enginePath = [tetexBinPath stringByAppendingString: enginePath];
        enginePath = [self absoluteEnginePath:enginePath];
        [args addObject: [sourcePath lastPathComponent]];
        }
    
// LatexCommandKey

    else if ([userEngine isEqualToString:@"pdflatex"]) {
        theProgramWithFlags = [[SUD stringForKey: LatexCommandKey] stringByExpandingTildeInPath];
        enginePath = [self separate:theProgramWithFlags into:args];
          //  [args addObject: [sourcePath lastPathComponent]];
          //   tetexBinPath = [[[SUD stringForKey:TetexBinPath] stringByExpandingTildeInPath] stringByAppendingString:@"/"];
          //   enginePath = [tetexBinPath stringByAppendingString: enginePath];
        enginePath = [self absoluteEnginePath:enginePath];
        [args addObject: [sourcePath lastPathComponent]];
        }

// LatexGSCommandKey
    
    else if ([userEngine isEqualToString:@"latex"]) {
            theProgramWithFlags = [[SUD stringForKey: LatexGSCommandKey] stringByExpandingTildeInPath];
            enginePath = [self separate:theProgramWithFlags into:args];
            //tetexBinPath = [[[SUD stringForKey:TetexBinPath] stringByExpandingTildeInPath] stringByAppendingString:@"/"];
            //enginePath = [tetexBinPath stringByAppendingString: enginePath];
            //[args addObject: sourcePath];;
            enginePath = [self absoluteEnginePath:enginePath];
            [args addObject: sourcePath];
            }
    
//  End of fix RMK
                      
    else {
            tempPath = [EnginePath stringByExpandingTildeInPath];
            enginePath = [[[tempPath stringByAppendingString:@"/"] stringByAppendingString: userEngine] stringByAppendingString:@".engine"];
            [args addObject: sourcePath];
            }

    __weak TSDocument *weakSelf = self;
    TSExperimentConsoleController *console = [self ensureExperimentConsole];
    if (!console.isWindowLoaded || NSApp.keyWindow != console.window)
        console.returnWindow = NSApp.keyWindow;
    [console startExecutable:enginePath ?: @"" arguments:args environment:env
                  directory:[fileURL URLByDeletingLastPathComponent]
                   encoding:self.scrapEffectiveEncoding title:scrapWindow.title ?: @"TeXShop"
                 completion:^(NSURL *pdfURL) {
        TSDocument *document = weakSelf;
        if (!document) return;
        if (![[NSFileManager defaultManager] fileExistsAtPath:pdfURL.path]) return;
        [document->scrapPDFKitView reShowWithPath:pdfURL.path];
        [document->scrapPDFWindow setHidesOnDeactivate:YES];
        [document->scrapPDFWindow makeKeyAndOrderFront:nil];
        [document->scrapPDFKitView didShowOutputWindow];
    }];
}

@end
