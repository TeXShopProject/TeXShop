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
 * $Id: TSPreviewWindow.m 260 2007-08-08 22:51:09Z richard_koch $
 *
 * Originally part of TSDocument. Broken out by dirk on Tue Jan 09 2001.
 *
 */

/*
 * Among other things, this window controls splitting of the Preview Window views.
 * Splitting is done here, and controls which affect both views simultaneously
 * are connected here. Many controls automatically use the active view without help.
 *
 * The TSDocument class is involved only slightly in splitting. It receives a few toolbar
 * commands to split the window, but immediately passes them to this class. It also
 * initializes *activeView when the nib is first expanded; from them on, active view
 * is set here from calls in split window or in the pdfkitview's activate routine.
 */

#import "UseMitsu.h"

#import <AppKit/AppKit.h>
#import "TSPreviewWindow.h"
#import "TSDocument.h"
#import "MyPDFView.h"
#import "MyPDFKitView.h"
#import "globals.h"
#import "TSPreviewSplitDivider.h"
#import "TSToolbarController.h"

#define ADJUST 7
#define ADJUST1 47

extern NSPanel *pageNumberWindow;


// In a split window, the part that the toolbar and the Preview menu work with has a
// thin line in the accent color along its inside edges, like a focus ring, while the
// window is key (#14). The line lies above the PDF and lets every click through.
@interface TSPreviewActivePartLine : NSView
@property (nonatomic) BOOL shown;
@property (weak) TSPreviewWindow *previewWindow;
@end

@implementation TSPreviewActivePartLine

- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)setShown:(BOOL)shown
{
    if (_shown == shown)
        return;
    _shown = shown;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Only on the screen: not in a PDF made from the view, for instance when a
    // selection on a rotated page is dragged out, nor when the view is printed.
    if (!self.shown || ![NSGraphicsContext currentContextDrawingToScreen])
        return;
    NSBezierPath *line = [NSBezierPath bezierPathWithRect: NSInsetRect(self.bounds, 1, 1)];
    line.lineWidth = 2;
    [[NSColor controlAccentColor] setStroke];
    [line stroke];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void)viewDidMoveToWindow
{
    if (!self.window)
        return;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification])
        [center addObserver: self selector: @selector(keyWindowChanged:) name: name object: self.window];
    [center addObserver: self selector: @selector(accentColorChanged:) name: NSSystemColorsDidChangeNotification object: nil];
    [self.previewWindow showActivePart];
}

- (void)keyWindowChanged:(NSNotification *)notification
{
    [self.previewWindow showActivePart];
}

- (void)accentColorChanged:(NSNotification *)notification
{
    self.needsDisplay = YES;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

@end

@implementation TSPreviewWindow


- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask backing:(NSBackingStoreType)backingType defer:(BOOL)flag
{
	id		result;
	NSColor	*backColor;
    
 	result = [super initWithContentRect:contentRect styleMask:styleMask backing:backingType defer:flag];
    
    self.firstTime = YES;

	// backColor = [NSColor lightGrayColor];
	backColor = [NSColor colorWithCalibratedRed:0.9 green:0.9 blue:0.9 alpha: 1.0];
	[self setBackgroundColor: backColor];

	CGFloat alpha = [SUD floatForKey: PreviewWindowAlphaKey];
	if (alpha < 0.999)
		[self setAlphaValue:alpha];

	self.activeView = nil;
	self.windowIsSplit = NO;
	self.willClose = NO;
    self.horizontal = YES;
    
    
	return result;
}


- (void)setActiveView:(PDFView *)activeView
{
    _activeView = activeView;
    [self showActivePart];
}

- (void)setWindowIsSplit:(BOOL)windowIsSplit
{
    _windowIsSplit = windowIsSplit;
    [self showActivePart];
}

// The line along a part, put on top of the part's own subviews.
static TSPreviewActivePartLine *TSActivePartLineInView(TSPreviewWindow *window, PDFView *view)
{
    TSPreviewActivePartLine *line = nil;
    for (NSView *subview in view.subviews)
        if ([subview isKindOfClass: [TSPreviewActivePartLine class]])
            line = (TSPreviewActivePartLine *)subview;
    if (!line) {
        line = [[TSPreviewActivePartLine alloc] initWithFrame: view.bounds];
        line.previewWindow = window;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview: line positioned: NSWindowAbove relativeTo: nil];
        [NSLayoutConstraint activateConstraints: @[
            [line.leadingAnchor constraintEqualToAnchor: view.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor: view.trailingAnchor],
            [line.topAnchor constraintEqualToAnchor: view.topAnchor],
            [line.bottomAnchor constraintEqualToAnchor: view.bottomAnchor]]];
    } else if (view.subviews.lastObject != line)
        [view addSubview: line positioned: NSWindowAbove relativeTo: nil];
    return line;
}

- (void)showActivePart
{
    for (PDFView *view in @[self.myPDFKitView ?: NSNull.null, self.myPDFKitView2 ?: NSNull.null]) {
        if (![view isKindOfClass: [PDFView class]])
            continue;
        BOOL shown = self.windowIsSplit && view == self.activeView && view.window.isKeyWindow;
        TSPreviewActivePartLine *line = nil;
        for (NSView *subview in view.subviews)
            if ([subview isKindOfClass: [TSPreviewActivePartLine class]])
                line = (TSPreviewActivePartLine *)subview;
        if (shown || line)
            TSActivePartLineInView(self, view).shown = shown;
    }
}

- (void)close
{
    TSDocument *theDocument = self.myDocument;
    
    if (theDocument.annotationsExist)
        {
        theDocument.annotationsExist = NO;
        [theDocument callSaveAnnotations];
        }
    
//	[self.myPDFKitView setDocument: nil];
//	[self.myPDFKitView2 setDocument: nil];
	self.willClose = YES;
    self.previewClosed = YES;
 // self.myDocument = nil;
    if ([theDocument skipTextWindow]) {
        self.myDocument = nil;
        [theDocument close];
        }
    
 //   self.myPDFKitView = nil;
 //   self.myPDFKitView2 = nil;
 //   self.activeView = nil;
    
	[super close];
}

- (void)resignMainWindow
{
    // A pinned link popup stays while another window is used, for instance to paste text
    // copied from it (#14).
    [(MyPDFKitView *)self.myPDFKitView cleanupMarqueeKeepingPinnedLinkPreview];
    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarqueeKeepingPinnedLinkPreview];
    [super resignMainWindow];
}

// Splitting or unsplitting changes the size of the panes; pinned link popups are brought back
// into view, and again once PDFKit has laid out the panes (#14).
- (void)keepPinnedLinkPreviewsInView
{
    [(MyPDFKitView *)self.myPDFKitView keepPinnedLinkPreviewInView];
    [(MyPDFKitView *)self.myPDFKitView2 keepPinnedLinkPreviewInView];
    __weak TSPreviewWindow *weakWindow = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TSPreviewWindow *window = weakWindow;
        [(MyPDFKitView *)window.myPDFKitView keepPinnedLinkPreviewInView];
        [(MyPDFKitView *)window.myPDFKitView2 keepPinnedLinkPreviewInView];
    });
}


- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWindowNumber
{
    [super orderWindow:place relativeTo:otherWindowNumber];
    // A user can reopen the preview while typesetting is still running, for
    // example through SyncTeX. Preserve the newly selected position on reload.
    if (place != NSWindowOut && self.isVisible)
        self.previewClosed = NO;
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)defaultFrame
{
	NSRect	newFrame;
	
	newFrame = defaultFrame;
	newFrame.origin.x = newFrame.origin.x + 200;
	
	newFrame.size.width = newFrame.size.width - 200;
	return newFrame;
}


/*
- (BOOL)makeFirstResponder:(NSResponder *)aResponder
{
	if (aResponder == self)
		return NO;
	else return [super makeFirstResponder: aResponder];
}
*/

- (void) becomeMainWindow
{
   self.willClose = NO;
	if([self.myDocument fileURL] != nil ) [self setTitle:[[[self.myDocument fileTitleName] stringByDeletingPathExtension] stringByAppendingString: @".pdf"]]; // added by Terada
	[super becomeMainWindow];

	[self.myDocument fixMacroMenuForWindowChange];
}


- (void) doTextMagnify: sender
{
    [self.myDocument doTextMagnify: sender];
}

- (void) doTextPage: sender
{
    [self.myDocument doTextPage: sender];
}

- (void) displayLog: sender
{
	[self.myDocument displayLog: sender];
}

- (void) displayConsole: sender
{
	[self.myDocument displayConsole: sender];
}

- (void) abort: sender
{
	[self.myDocument abort: sender];
}

- (void) trashAUXFiles: sender
{
	[self.myDocument trashAUXFiles: sender];
}

- (void) toggleSyntaxColor: (id)sender
{
    [self.myDocument toggleSyntaxColor: sender];
}


- (void) runPageLayout: sender
{
	[self.myDocument runPageLayout: sender];
}

- (void) printDocument: sender
{
	[self.myDocument printDocument: sender];
}

- (void) printSource: sender
{
	[self.myDocument printSource: sender];
}

- (void) doTypeset: sender
{
	[self.myDocument doTypeset: sender];
}

- (void) doAlternateTypeset: sender
{
    [self.myDocument doAlternateTypeset: sender];
}

- (void) flipShowSync: sender
{
	[self.myDocument flipShowSync: sender];
}

- (void) doTex: sender
{
	[self.myDocument doTex: sender];
}

- (void) doLatex: sender
{
	[self.myDocument doLatex: sender];
}

- (void) doBibtex: sender
{
	[self.myDocument doBibtex: sender];
}

- (void) doIndex: sender
{
	[self.myDocument doIndex: sender];
}

- (void) doMetapost: sender
{
	[self.myDocument doMetapost: sender];
}

/*
- (void) doContext: sender
{
	[self.myDocument doContext: sender];
}
*/

- (void) doMetaFont: sender
{
	[self.myDocument doMetaFont: sender];
}

- (void) previousPage: sender
{
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] previousPage: sender];
	else
		[[self.myDocument pdfView] previousPage: sender];
}

- (void) nextPage: sender;
{	
	
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] nextPage: sender];
	else
		[[self.myDocument pdfView] nextPage: sender];
}


- (void) doChooseMethod: sender
{
	[self.myDocument doChooseMethod: sender];
}

- (void) doError: sender
{
	[self.myDocument doError: sender];
}

- (void) setProjectFile: sender
{
	[self.myDocument setProjectFile: sender];
}

- (void) rotateClockwise: sender
{
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] rotateClockwise: sender];
	else {
		[[self.myDocument pdfView] rotateClockwise: sender];
	}
}

- (void) rotateCounterclockwise: sender
{
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] rotateCounterclockwise: sender];
	else {
		[[self.myDocument pdfView] rotateCounterclockwise: sender];
	}
}

////////////////////// key movement ///////////////////////////////////

- (void) firstPage: sender;
{	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] firstPage: sender];
	else
		[[self.myDocument pdfView] firstPage: sender];
}

- (void) lastPage: sender
{
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] lastPage: sender];
	else
		[[self.myDocument pdfView] lastPage: sender];
}

- (void) up: sender
{
	if (![self.myDocument fromKit]) {
		[[self.myDocument pdfView] up: sender];
	}
}

- (void) down: sender
{
	if (![self.myDocument fromKit]) {
		[[self.myDocument pdfView] down: sender];
	}
}

- (void) top: sender
{
	if (![self.myDocument fromKit]) {
		[[self.myDocument pdfView] top: sender];
	}
}

- (void) bottom: sender
{
	if (![self.myDocument fromKit]) {
		[[self.myDocument pdfView] bottom: sender];
	}
}

// mitsu 1.29 (O)
- (void) left: sender
{
	if (![self.myDocument fromKit]) {
		[[self.myDocument pdfView] left: sender];
	}
}

- (void) right: sender
{
	if (![self.myDocument fromKit]) {
		[[self.myDocument pdfView] right: sender];
	}
}



- (void)doMove: (id)sender
{
    [self.myDocument doMove:sender];
}


////////// end key movement /////////////////////////

- (void) orderOut:sender
{
	self.willClose = YES;
	if ([self.myDocument externalEditor]) {
		if (! [self.myDocument getWillClose]) {
			[self.myDocument setWillClose: YES];
			[self.myDocument close];
		}
	}
	else if (([self.myDocument documentType] != isTeX) && ([self.myDocument documentType] != isOther)) {
		if (! [self.myDocument getWillClose]) {
			[self.myDocument setWillClose: YES];
			[self.myDocument close];
		}		
	}
	else
		[super orderOut: sender];
}

- (void)associatedWindow:(id)sender
{
    if ([self.myDocument externalEditor])
        return;
 	if ([self.myDocument documentType] == isTeX) {
        
        if ([self.myDocument experimentActive])
           [self.myDocument switchExperimentWindows];
        
        else if ([self.myDocument getCallingWindow] == nil)
          [[self.myDocument textWindow] makeKeyAndOrderFront: self];
            
  		else
			[[self.myDocument getCallingWindow] makeKeyAndOrderFront: self];

		}
}

- (void)sendEvent:(NSEvent *)theEvent
{

    
	 if (self.willClose) {
		[super sendEvent: theEvent];
		return;
	}
    


	if ([self.myDocument fromKit] && ([theEvent type] == NSEventTypeKeyDown) && ([theEvent modifierFlags] & NSCommandKeyMask)) {
		if ([[theEvent characters] characterAtIndex:0] == '[') {
			// [[self.myDocument pdfKitView] goBack: self];
			[self.activeView zoomOut:nil];
			return;
		} 
		
		if ([[theEvent characters] characterAtIndex:0] == ']') {
			// [[self.myDocument pdfKitView] goForward: self];
			[self.activeView zoomIn:nil];
			return;
		} 
	
	}


    
#ifdef IMMEDIATEMAGNIFY
  if (([self.myDocument fromKit]) && ([theEvent type] == NSEventTypeLeftMouseDown) && ([[self.myDocument pdfKitView] toolIsMagnification]))
  {
      NSUInteger modifiers = NSEvent.modifierFlags;
      NSUInteger modifiersPressed = modifiers & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption);
      if (! modifiersPressed)
      {
          NSPoint thePoint = [theEvent locationInWindow];
          NSPoint aPoint = [[self.myDocument pdfKitView] convertPoint:thePoint fromView:nil];
          NSView *aView = [self.myDocument pdfKitView];
          NSRect Inside = aView.bounds;
          Inside = NSInsetRect(Inside, 15, 15);
          BOOL inPDF = [aView mouse: aPoint inRect: Inside];
          // A click in a pinned link popup goes to the popup, which handles every tool (#14).
          if (inPDF && ! [(MyPDFKitView *)aView pinnedLinkPreviewContainsWindowPoint: thePoint])
          {
              if ([self isMainWindow])
              {
                  [[self.myDocument pdfKitView] fancyMouseDown: theEvent];
                  // [super sendEvent: theEvent]; this call kills scrolling by trackpad in the pdf window
                  return;
              }
          }
      }
   }
#endif
 
	if (![self.myDocument fromKit]) {
		
		unichar	theChar;

		if ([theEvent type] == NSEventTypeKeyDown) {

			/*
			if (([theEvent modifierFlags] & NSControlKeyMask) &&
				([myDocument documentType] == isTeX) &&
				([[theEvent charactersIgnoringModifiers] isEqualToString:@"1"])) {

				[[myDocument textWindow] makeKeyAndOrderFront: self];
				return;
			}
			*/

			theChar = [[theEvent characters] characterAtIndex:0];

			switch (theChar) {

#ifdef MITSU_PDF

				case NSUpArrowFunctionKey: [self up:self]; return;

				case NSDownArrowFunctionKey: [self down:self]; return;

				case NSLeftArrowFunctionKey: [self left: self]; return;// mitsu 1.29 (O) changed from previousPage

				case NSRightArrowFunctionKey: [self right: self]; return;// mitsu 1.29 (O) changed from nextPage

				case NSPageUpFunctionKey: [self top:self]; return;

				case NSPageDownFunctionKey: [self bottom:self]; return;

#else

				case NSLeftArrowFunctionKey: [self previousPage: self]; return;

				case NSRightArrowFunctionKey: [self nextPage: self]; return;

#endif

				case NSHomeFunctionKey: [self firstPage: self]; return;

				case NSEndFunctionKey: [self lastPage: self]; return;

				case ' ':
					if (([theEvent modifierFlags] & NSShiftKeyMask) == 0)
						[self nextPage: self];
					else
						[self previousPage: self];
					return;
			}
		}


#ifdef MITSU_PDF

		else if ([theEvent type] == NSEventTypeFlagsChanged) // mitsu 1.29 (S2)
		{
			[[self.myDocument pdfView] flagsChanged: theEvent];
			return;
		}
		else if ([theEvent type] == NSEventTypeLeftMouseDown) // mitsu 1.29 (O) resize PDF view
		{
			// check if mouse was in vertical scroller's knob
			MyPDFView *pdfView = [self.myDocument pdfView];
			NSScroller *scroller = [[pdfView enclosingScrollView] verticalScroller];
			if (([scroller testPart: [theEvent locationInWindow]] == NSScrollerKnob) &&
				([self.myDocument documentType] == isTeX || [self.myDocument documentType] == isPDF) &&
				([pdfView pageStyle] == PDF_MULTI_PAGE_STYLE ||
				 [pdfView pageStyle] == PDF_DOUBLE_MULTI_PAGE_STYLE) &&
				([pdfView rotationAmount] == 0 || [pdfView rotationAmount] == 180))
			{
				// create a small window displaying page number
				NSRect aRect = [scroller rectForPart: NSScrollerKnob];
				aRect = [scroller convertRect: aRect toView: nil]; // use rect not point
				aRect = [self convertRectToScreen: aRect];
				aRect.origin.x -= PAGE_WINDOW_H_OFFSET;
				aRect.origin.y += aRect.size.height/2 + PAGE_WINDOW_V_OFFSET;
				aRect.size.width = PAGE_WINDOW_WIDTH;
				aRect.size.height = PAGE_WINDOW_HEIGHT;
				pageNumberWindow = [[NSPanel alloc] initWithContentRect: aRect
															  styleMask: NSBorderlessWindowMask | NSUtilityWindowMask
																backing: NSBackingStoreBuffered //NSBackingStoreRetained
																  defer: NO];
				[pageNumberWindow setHasShadow: PAGE_WINDOW_HAS_SHADOW];
				[pageNumberWindow orderFront: nil];
				[pageNumberWindow setFloatingPanel: YES];
				[[self.myDocument pdfView] updateCurrentPage]; // draw page number

				[super sendEvent: theEvent]; // let the scroller handle the situation

				[pageNumberWindow close];
				pageNumberWindow = nil;
				return;
			}
		}

#endif
	}
	[super sendEvent: theEvent];
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    
	if ([anItem action] == @selector(splitWindow:)) {
		if (self.windowIsSplit)
			[anItem setState:NSOnState];
		else
			[anItem setState:NSOffState];
		return YES;
	}
    
    if ([anItem action] == @selector(toggleLinkPopups:)) {
        if (self.myDocument)
            return [self.myDocument validateMenuItem:anItem];
        MyPDFKitView *aView;
        aView = (MyPDFKitView *)self.myPDFKitView;
        
        if (aView.skipLinks)
            [anItem setState:NSOffState];
        else
            [anItem setState:NSOnState];
        return YES;
    }
    
    /*
    if ([anItem action] == @selector(toggleAnnotationMenu:)) {
        MyPDFKitView *aView;
        aView = (MyPDFKitView *)self.myPDFKitView;
        
        if (aView.useAnnotationMenu)
            [anItem setState:NSOnState];
        else
            [anItem setState:NSOffState];
        
        return YES;
    }
    */

	if ([anItem action] == @selector(displayLatexPanel:))
		return NO;
	if ([anItem action] == @selector(displayMatrixPanel:))
		return NO;

#ifdef MITSU_PDF
#else
	if ([anItem action] == @selector(rotateClockwise:) ||
		[anItem action] == @selector(rotateCounterclockwise:))
		return (([myDocument documentType] == isTeX) || ([myDocument documentType] == isPDF));
#endif

	if ([anItem action] == @selector(doError:) ||
		[anItem action] == @selector(printSource:))
		return ((![self.myDocument externalEditor]) && ([self.myDocument documentType] == isTeX));

	if ([anItem action] == @selector(setProjectFile:))
		return ([self.myDocument documentType] == isTeX);

	if ([self.myDocument documentType] != isTeX) {
		if ([anItem action] == @selector(saveDocument:))
			return ([self.myDocument documentType] == isOther);
		if ([anItem action] == @selector(doTex:) ||
			[anItem action] == @selector(doLatex:) ||
			[anItem action] == @selector(doBibtex:) ||
			[anItem action] == @selector(doIndex:) ||
			[anItem action] == @selector(doMetapost:) ||
			[anItem action] == @selector(doContext:) ||
			[anItem action] == @selector(doMetaFont:) ||
			[anItem action] == @selector(doTypeset:))
			return NO;
		if ([anItem action] == @selector(printDocument:))
			return (([self.myDocument documentType] == isPDF) ||
					([self.myDocument documentType] == isJPG) ||
					([self.myDocument documentType] == isTIFF));
	}

#ifdef MITSU_PDF

		// mitsu 1.29 (O)
	if ([anItem action] == @selector(changePageStyle:)) {
		
		if ([self.myDocument fromKit]) return [self.myDocument validatePreviewLayoutItem:anItem];
        return (([self.myDocument documentType] == isTeX) || ([self.myDocument documentType] == isPDF));
	}

	if ([anItem action] == @selector(copy:) || [anItem action] == @selector(saveSelectionToFile:))
		return ([[self.myDocument pdfView] hasSelection]);
	// end mitsu 1.29 (O)

#endif

	return [super validateMenuItem: anItem];
}


- (TSDocument *)document
{
	return self.myDocument;
}

#ifdef MITSU_PDF


// mitsu 1.29 (O)
- (void)changePageStyle: (id)sender
{
    
	if ([self.myDocument fromKit])
		[self.myDocument changePreviewLayout:sender];
	else
		[[self.myDocument pdfView] changePageStyle: sender];
}

- (void)changePDFViewSize: (id)sender
{	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] changePDFViewSize: sender];
	else
		[[self.myDocument pdfView] changePDFViewSize: sender];
}

- (void)zoomIn: (id)sender
{
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] zoomIn: sender];
}

- (void)zoomOut: (id)sender
{
	
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] zoomOut: sender];
}

- (void)fullscreen: (id)sender
{
	if ([self.myDocument fromKit])
		[self.myDocument fullscreen: sender];
}

- (void) savePreviewPosition: sender
{
	[self.myDocument savePreviewPosition];
}


- (void) saveHTMLPosition: sender
{
    [self.myDocument saveHTMLPosition: sender];
}

- (void) showHTMLWindow: sender
{
    [self.myDocument showHTMLWindow: sender];
}
 

- (void) savePortablePreviewPosition: sender
{
	[self.myDocument savePortablePreviewPosition];
}


- (void)copy: (id)sender
{
	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] copy: sender];
	else
		[[self.myDocument pdfView] copy: sender];
}

-(void)saveSelectionToFile: (id)sender
{	if ([self.myDocument fromKit])
		[[self.myDocument pdfKitView] saveSelectionToFile: sender];
	else
		[[self.myDocument pdfView] saveSelectionToFile: sender];
}
// end mitsu 1.29 (O)
// end mitsu 1.29


#endif

/*
 - (void)moveSplitToCorrectSpot:(NSInteger)index;
 {
     PDFPage        *aPage;
     
     aPage = [[self document] pageAtIndex: index];
     [self goToPage: aPage];
     
 }

 */


- (void)switchViews;

{
    NSInteger       pageIndex1;
    NSRect          visibleRect1;
    MyPDFKitView    *aView;
    
    if (self.windowIsSplit) {
        [self switchSplitParts];
      }
   
    else {
        /*
         [self mainSplitPdfKitWindow];
         [self switchViews];
         [self mainSplitPdfKitWindow];
       */
        
        aView = (MyPDFKitView *)self.myPDFKitView;
        pageIndex1 = [[aView document] indexForPage:[aView currentPage]];
        visibleRect1 = [[[aView documentView] enclosingScrollView] documentVisibleRect];
        
        if (aView.oldUsed)
        {
            [aView goToPage: [[aView document] pageAtIndex: aView.oldIndex]];
            if (aView.doScroll)
                [[aView documentView] scrollRectToVisible: aView.oldVisibleRect];
            //else
               // NSLog(@"Did Not Scroll");
            aView.doScroll = YES;
            aView.oldIndex = pageIndex1;
            aView.oldVisibleRect = visibleRect1;
        }
        else
        {
            aView.oldUsed = YES;
            aView.oldIndex = pageIndex1;
            aView.oldVisibleRect = visibleRect1;
        }
        
         
     }
        
 }

// The two parts of a split window change places with everything they show (#25): the place
// at the top edge (#23), the display format, the magnification, the selection, a pinned link
// popup (#14) and the size of the part, so the divider moves, and switching again gives back
// the first arrangement. The top (or left) view stays the one that remains when the window is
// unsplit, so it now holds what the other part showed.
- (void)switchSplitParts
{
    MyPDFKitView *upperView = (MyPDFKitView *)self.myPDFKitView;
    MyPDFKitView *lowerView = (MyPDFKitView *)self.myPDFKitView2;
    NSSplitView *splitView = self.pdfKitSplitView;
    if (upperView.superview != splitView || lowerView.superview != splitView || splitView.subviews.count != 2)
        return;
    NSWindow *window = upperView.window;

    [upperView cleanupMarqueeKeepingPinnedLinkPreview];
    [lowerView cleanupMarqueeKeepingPinnedLinkPreview];

    TSPreviewPanePlace upper = TSPreviewPaneCapture(upperView);
    TSPreviewPanePlace lower = TSPreviewPaneCapture(lowerView);
    NSInteger upperStyle = upperView.pageStyle, lowerStyle = lowerView.pageStyle;
    NSInteger upperFirstStyle = upperView.firstPageStyle, lowerFirstStyle = lowerView.firstPageStyle;
    NSInteger upperResize = upperView.resizeOption, lowerResize = lowerView.resizeOption;
    BOOL upperAutoScales = upperView.autoScales, lowerAutoScales = lowerView.autoScales;
    CGFloat upperScale = upperView.scaleFactor, lowerScale = lowerView.scaleFactor;
    PDFSelection *upperSelection = upperView.currentSelection, *lowerSelection = lowerView.currentSelection;
    NSRect upperFrame = [upperView convertRect:upperView.bounds toView:nil];
    NSRect lowerFrame = [lowerView convertRect:lowerView.bounds toView:nil];
    NSRect upperPopupFrame = NSZeroRect, lowerPopupFrame = NSZeroRect;
    TSLinkPreviewView *upperPopup = [upperView detachPinnedLinkPreviewWithWindowFrame: &upperPopupFrame];
    TSLinkPreviewView *lowerPopup = [lowerView detachPinnedLinkPreviewWithWindowFrame: &lowerPopupFrame];
    NSResponder *responder = window.firstResponder;
    BOOL upperActive = [responder isKindOfClass:[NSView class]] && [(NSView *)responder isDescendantOf:upperView];
    BOOL lowerActive = [responder isKindOfClass:[NSView class]] && [(NSView *)responder isDescendantOf:lowerView];

    // Each part gets the size of the other one, so the divider moves to the other side.
    CGFloat lowerExtent = splitView.isVertical ? NSWidth(lowerView.frame) : NSHeight(lowerView.frame);
    CGFloat start = splitView.isVertical ? NSMinX(splitView.bounds) : NSMinY(splitView.bounds);
    [splitView setPosition:start + lowerExtent ofDividerAtIndex:0];
    [splitView layoutSubtreeIfNeeded];

    // Each view takes the display format and magnification of the other part. A magnification
    // that fits the page to the window gives the same value, since the size comes along.
    MyPDFKitView *views[2] = {upperView, lowerView};
    NSInteger styles[2] = {lowerStyle, upperStyle}, firstStyles[2] = {lowerFirstStyle, upperFirstStyle};
    NSInteger resizes[2] = {lowerResize, upperResize};
    BOOL autoScales[2] = {lowerAutoScales, upperAutoScales};
    CGFloat scales[2] = {lowerScale, upperScale};
    for (int i = 0; i < 2; i++) {
        MyPDFKitView *view = views[i];
        [view setFirstPageStyle:firstStyles[i]];
        if (view.pageStyle != styles[i]) {
            [view setPageStyle:styles[i]];
            [view setupPageStyle];
        }
        [view setResizeOption:resizes[i]];
        if (autoScales[i])
            [view setAutoScales:YES];
        else {
            [view setAutoScales:NO];
            [view setMagnification:scales[i]];
        }
    }
    [upperView setCurrentSelection:lowerSelection];
    [lowerView setCurrentSelection:upperSelection];

    TSPreviewPaneRestore(upperView, lower);
    TSPreviewPaneRestore(lowerView, upper);

    // A pinned popup keeps its place in its part, which is now at the other side.
    NSRect newUpperFrame = [upperView convertRect:upperView.bounds toView:nil];
    NSRect newLowerFrame = [lowerView convertRect:lowerView.bounds toView:nil];
    if (lowerPopup)
        [upperView attachPinnedLinkPreview:lowerPopup windowFrame:NSOffsetRect(lowerPopupFrame,
            NSMinX(newUpperFrame) - NSMinX(lowerFrame), NSMaxY(newUpperFrame) - NSMaxY(lowerFrame))];
    if (upperPopup)
        [lowerView attachPinnedLinkPreview:upperPopup windowFrame:NSOffsetRect(upperPopupFrame,
            NSMinX(newLowerFrame) - NSMinX(upperFrame), NSMaxY(newLowerFrame) - NSMaxY(upperFrame))];

    // The active part stays active where it now is. Without the keyboard focus in either part,
    // as when it is in the search field, the focus stays where it is, and the toolbar, the menus
    // and the search results still follow the part.
    MyPDFKitView *active = nil;
    if (upperActive || self.activeView == upperView)
        active = lowerView;
    else if (lowerActive || self.activeView == lowerView)
        active = upperView;
    if (!(upperActive || lowerActive) || ![window makeFirstResponder:active])
        [active becomeActiveView];
    [self keepPinnedLinkPreviewsInView];
}

// Split Window with Link (#31). The part with the link stays where it is, and the other part
// goes to the target of the link as if the link were clicked there, so Back takes it back.
// An unsplit window is first split as by Split Window. The other part keeps its display
// format and magnification. If it is too small to show anything, as when the divider has
// been dragged to the edge of the window, the divider first moves to the middle. The other
// part becomes the active view, which Back and Forward and the toolbar work with.
- (void)showLinkDestination: (PDFDestination *)destination besideView: (PDFView *)view
{
    // The PDF may have been reloaded while the menu was open; the target then belongs to the old one.
    if (destination.page == nil || destination.page.document == nil || destination.page.document != view.document)
        return;
    if (! self.windowIsSplit) {
        if (view != self.myPDFKitView)
            return;
        [self splitPdfKitWindow: nil];
    }
    MyPDFKitView *linkView = (MyPDFKitView *)view;
    MyPDFKitView *otherView = (MyPDFKitView *)(view == self.myPDFKitView ? self.myPDFKitView2 : self.myPDFKitView);
    NSSplitView *splitView = self.pdfKitSplitView;
    if (! self.windowIsSplit || linkView.superview != splitView || otherView.superview != splitView || splitView.subviews.count != 2)
        return;
    if (otherView.document != linkView.document)
        return;
    NSWindow *window = linkView.window;

    CGFloat whole = splitView.isVertical ? NSWidth(splitView.bounds) : NSHeight(splitView.bounds);
    CGFloat otherExtent = splitView.isVertical ? NSWidth(otherView.frame) : NSHeight(otherView.frame);
    if (otherExtent < whole / 10) {
        TSPreviewPanePlace place = TSPreviewPaneCapture(linkView);
        CGFloat start = splitView.isVertical ? NSMinX(splitView.bounds) : NSMinY(splitView.bounds);
        [splitView setPosition: start + round((whole - splitView.dividerThickness) / 2) ofDividerAtIndex: 0];
        [splitView layoutSubtreeIfNeeded];
        TSPreviewPaneRestore(linkView, place);
    }

    [otherView cleanupMarqueeKeepingPinnedLinkPreview];
    [otherView goToDestination: destination];

    NSResponder *responder = window.firstResponder;
    BOOL focusInParts = [responder isKindOfClass: [NSView class]] &&
        ([(NSView *)responder isDescendantOf: linkView] || [(NSView *)responder isDescendantOf: otherView]);
    if (! focusInParts || ! [window makeFirstResponder: otherView])
        [otherView becomeActiveView];
}

- (void)switchSplitViews: (id)sender
{
    [self switchViews];
}

- (void)toggleLinkPopups:(id)sender;
{
    MyPDFKitView    *aView, *aView2;
    
    if (self.myDocument) {
        [self.myDocument toggleLinkPopups:sender];
        return;
    }
    aView = (MyPDFKitView *)self.myPDFKitView;
    aView2 = (MyPDFKitView *)self.myPDFKitView2;
    [aView changeLinkPopups];
    [aView2 changeLinkPopups];
}

/*
- (void)toggleAnnotationMenu:(id)sender;
{
    MyPDFKitView    *aView;
    
    aView = (MyPDFKitView *)self.myPDFKitView;
    
    [aView changeAnnotationMenu];
    
}
*/



/*

- (void) mainSplitPdfKitWindow
{
    NSSize        theSize, newSize1, newSize2;
    NSRect        theFrame, theFrame1, theFrame2;
    NSRect      myVisibleRect;
    double      myScrollAmount;
    double      mag, magnification;
    BOOL        result;
    double      temp1, temp2, myHeight, myHeight1;
    MyPDFKitView    *aView;
    
// Fix encrypted pdf bug
    MyPDFKitView *firstView;
    MyPDFKitView *secondView;
    
    firstView = (MyPDFKitView *)self.myPDFKitView;
    secondView = (MyPDFKitView *)self.myPDFKitView2;
    
    if (self.firstTime)
    {
        self.firstTime = NO;
        [firstView removeConstraints: firstView.constraints];
        [secondView removeConstraints: secondView.constraints];
    }
// end of fix
    
// "saveLocation" below saves index, documentview's visualRect, and documentview's bounds
 
    if (self.windowIsSplit)
        {
            [(MyPDFKitView *)self.myPDFKitView saveLocation];
            [(MyPDFKitView *)self.myPDFKitView2 saveLocation];
            ((MyPDFKitView *)self.myPDFKitView).locationSaved = YES;
            ((MyPDFKitView *)self.myPDFKitView2).locationSaved = YES;
        }
    else {
        [(MyPDFKitView *)self.myPDFKitView saveLocation];
    }
    
    
    [(MyPDFKitView *)self.myPDFKitView cleanupMarquee: YES];
    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarquee: YES];
    
    
    if (self.windowIsSplit) {
        self.windowIsSplit = NO;
        self.activeView = self.myPDFKitView;
        result = [self.activeView becomeFirstResponder];
        [(MyPDFKitView *)self.activeView resetSearchDelegate];
    }
    else {
        self.windowIsSplit = YES;
        self.activeView = self.myPDFKitView;
        }
    
     
    if (self.windowIsSplit) {
        theFrame = [self.myPDFKitView frame];
        newSize1.width = theFrame.size.width;
        newSize1.height = 100;
        newSize2 = newSize1;
        if ((self.horizontal) && ((MyPDFKitView *)self.myPDFKitView2).horizontalSplitSaved)
                {
                    newSize1.height = ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight1;
                    newSize2.height = ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight2;
                }
        if ((! self.horizontal) && ((MyPDFKitView *)self.myPDFKitView2).verticalSplitSaved)
                {
                    newSize1.width = ((MyPDFKitView *)self.myPDFKitView2).verticalWidth1;
                    newSize2.width = ((MyPDFKitView *)self.myPDFKitView2).verticalWidth2;
                }
        [self.myPDFKitView setFrameSize:newSize1];
        [self.myPDFKitView2 setFrameSize:newSize2];
        
        
        [self.pdfKitSplitView addSubview: self.myPDFKitView2];
         [self.pdfKitSplitView adjustSubviews];
        
        [(MyPDFKitView *)self.myPDFKitView2 setPageStyle:[(MyPDFKitView *)self.myPDFKitView pageStyle]];
        [(MyPDFKitView *)self.myPDFKitView2 setFirstPageStyle:[(MyPDFKitView *)self.myPDFKitView firstPageStyle]];
        if ( [(MyPDFKitView *)self.myPDFKitView resizeOption] == NEW_PDF_FIT_TO_NONE)
          [(MyPDFKitView *)self.myPDFKitView2 setMagnification: [(MyPDFKitView *)self.myPDFKitView magnification]];
        else {
            [(MyPDFKitView *)self.myPDFKitView2 setResizeOption:[(MyPDFKitView *)self.myPDFKitView resizeOption]];
            [(MyPDFKitView *)self.myPDFKitView2 setupMagnificationStyle];
            }
        [(MyPDFKitView *)self.myPDFKitView2 setupPageStyle];
       //  [(MyPDFKitView *)self.myPDFKitView2 setupMagnificationStyle];

        if ([self.myPDFKitView2 document] == nil) {
            // [[self.myPDFKitView document] retain];
            [self.myPDFKitView2 setDocument:[self.myPDFKitView document]];
                   }
        [(MyPDFKitView *)self.myPDFKitView2 moveSplitToCorrectSpot:[(MyPDFKitView *)self.myPDFKitView index]];
    }
    else
    {
        
        if (self.horizontal)
            {
                theFrame1 = [self.myPDFKitView frame];
                theFrame2 = [self.myPDFKitView2 frame];
                // tempBounds = [self.myPDFKitView2 bounds];
                temp1 = theFrame1.size.height;
                temp2 = theFrame2.size.height;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalSplitSaved = YES;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight1 = temp1;
               // ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight2 = temp2;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight2 = temp2;
                // [((MyPDFKitView *)self.myPDFKitView2) documentView].bounds = tempBounds;
                
                // theScale = ((MyPDFKitView *)self.myPDFKitView2).scaleFactor;
                // ((MyPDFKitView *)self.myPDFKitView2).scale = theScale;
            }
        else
            {
                theFrame1 = [self.myPDFKitView frame];
                theFrame2 = [self.myPDFKitView2 frame];
                // tempBounds = [self.myPDFKitView2 bounds];
                temp1 = theFrame1.size.width;
                temp2 = theFrame2.size.width;
                ((MyPDFKitView *)self.myPDFKitView2).verticalSplitSaved = YES;
                ((MyPDFKitView *)self.myPDFKitView2).verticalWidth1 = temp1;
                ((MyPDFKitView *)self.myPDFKitView2).verticalWidth2 = temp2;
             }
        [self.myPDFKitView2 removeFromSuperview];
        theFrame = [self.myPDFKitView frame];
        theSize.width = theFrame.size.width;
        theSize.height = self.frame.size.height;
        [self.myPDFKitView setFrameSize:theSize];
    }
    
  
    
    if (self.windowIsSplit)
        {
            if (self.horizontal)
            {
 
            myVisibleRect = ((MyPDFKitView *)self.myPDFKitView).documentView.visibleRect;
            myHeight = ((MyPDFKitView *)self.myPDFKitView2).documentView.visibleRect.size.height;
            myHeight1 = self.pdfKitSplitView.dividerThickness;
            myScrollAmount = myHeight + myHeight1 - 2;
         
            
            myVisibleRect.origin.y = myVisibleRect.origin.y + myScrollAmount;
            [[((MyPDFKitView *)self.myPDFKitView) documentView] scrollRectToVisible: myVisibleRect];
            }
            else
                [(MyPDFKitView *)self.myPDFKitView restoreLocation];
            
            if (((MyPDFKitView *)self.myPDFKitView2).locationSaved)
                [(MyPDFKitView *)self.myPDFKitView2 restoreLocation];
        }
    else
    {
        if (self.horizontal)
        {
            //    [(MyPDFKitView *)self.myPDFKitView restoreLocation];
        
        myVisibleRect = ((MyPDFKitView *)self.myPDFKitView).documentView.visibleRect;
            
            
        myHeight = ((MyPDFKitView *)self.myPDFKitView2).documentView.visibleRect.size.height;
        
        
  //      NSRect myHeightV = ((MyPDFKitView *)self.myPDFKitView2).documentView.visibleRect;
 //      double myScaleFactor = ((MyPDFKitView *)self.myPDFKitView2).scaleFactor;
 //      double scaleFactorLower = myScaleFactor;
 //      NSLog(@"height of lower half %f", myHeightV.size.height);
 //      NSLog(@"scalefactor of lower half %f", myScaleFactor);
            
 //       myHeightV = ((MyPDFKitView *)self.myPDFKitView).documentView.visibleRect;
 //       myScaleFactor = ((MyPDFKitView *)self.myPDFKitView).scaleFactor;
 //       NSLog(@"height of upper half %f", myHeightV.size.height);
 //       NSLog(@"scalefactor of upper half %f", myScaleFactor);
            
       // NSRect visibleRectInWindow = [self convertRect:myHeightV toView:nil];
        
            
        myHeight1 = self.pdfKitSplitView.dividerThickness;
             
        myScrollAmount = myHeight + myHeight1 + 35;
           
        // myScrollAmount = myHeight * scaleFactorLower + myHeight1;
            
         myVisibleRect.origin.y = myVisibleRect.origin.y - myScrollAmount;
        [[((MyPDFKitView *)self.myPDFKitView) documentView] scrollRectToVisible: myVisibleRect];
        }
        else
            
            [(MyPDFKitView *)self.myPDFKitView restoreLocation];
        
    }
    
}

*/

- (void) mainSplitPdfKitWindow
{
    NSSize        theSize, newSize1, newSize2;
    NSRect        theFrame, theFrame1, theFrame2;
    BOOL        result;
    double      temp1, temp2;
    BOOL        splitInMiddle;
    BOOL        topToBottom;
    TSLinkPreviewView *movedPreview = nil;
    NSRect      movedPreviewFrame = NSZeroRect;
    
    if (self.previewSplitDivider == nil && self.pdfKitSplitView != nil)
        self.previewSplitDivider = [[TSPreviewSplitDivider alloc] initWithSplitView:self.pdfKitSplitView];
    
    splitInMiddle = NO;
    topToBottom = NO;
    if (([NSEvent modifierFlags ] & NSEventModifierFlagShift) && ([NSEvent modifierFlags ] & NSEventModifierFlagControl))
    {
        splitInMiddle = YES;
    }
    
    else if ([NSEvent modifierFlags ] & NSEventModifierFlagShift)
    {
        topToBottom = YES;
        splitInMiddle = YES;
    }
    
// FIX ENCRYPTED PDF BUG
    
    MyPDFKitView *firstView;
    MyPDFKitView *secondView;
    
    firstView = (MyPDFKitView *)self.myPDFKitView;
    secondView = (MyPDFKitView *)self.myPDFKitView2;
    
    if (splitInMiddle)
    {
        [firstView autoScales];
        [secondView autoScales];
    }
    
    if (self.firstTime)
    {
        self.firstTime = NO;
        [firstView removeConstraints: firstView.constraints];
        [secondView removeConstraints: secondView.constraints];
    }
    
// END OF ENCRYPTED PDF BUG FIX
    
// SAVE CURRENT LOCATIONS FOR LATER RESTORE
    
    // The first pane keeps the place at its top edge where it is on the screen (#23).
    TSPreviewPanePlace firstTop = TSPreviewPaneCapture(firstView);
    
    // The second pane shows the same place again when the window is split next time.
    if (self.windowIsSplit)
        {
            [secondView saveLocation];
            secondView.locationSaved = YES;
        }
    
    
// REVISE self.windowIsSplit FOR SPLITING, BUT DO NOT YET SPLIT
    
    
    [(MyPDFKitView *)self.myPDFKitView cleanupMarqueeKeepingPinnedLinkPreview];
    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarqueeKeepingPinnedLinkPreview];
    
    
    if (self.windowIsSplit) {
        self.windowIsSplit = NO;
        self.activeView = self.myPDFKitView;
        result = [self.activeView becomeFirstResponder];
        [(MyPDFKitView *)self.activeView resetSearchDelegate];
    }
    else {
        self.windowIsSplit = YES;
        self.activeView = self.myPDFKitView;
        }
    
// ACTUALLY SPLIT OR UNSPLIT THE WINDOW
    

    if (self.windowIsSplit) {  // THIS SPLITS THE WINDOW
        
        // FORCE SPLIT BAR TO THE MIDDLE OF THE WINDOW
        
        theFrame = [self.myPDFKitView frame];
        newSize1.width = theFrame.size.width;
        newSize1.height = 100;
        newSize2 = newSize1;
        if ((self.horizontal) && (! splitInMiddle) && ((MyPDFKitView *)self.myPDFKitView2).horizontalSplitSaved)
                {
                    newSize1.height = ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight1;
                    newSize2.height = ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight2;
                }
        if ((! self.horizontal) && ((MyPDFKitView *)self.myPDFKitView2).verticalSplitSaved)
                {
                    newSize1.width = ((MyPDFKitView *)self.myPDFKitView2).verticalWidth1;
                    newSize2.width = ((MyPDFKitView *)self.myPDFKitView2).verticalWidth2;
                }
        [self.myPDFKitView setFrameSize:newSize1];
        [self.myPDFKitView2 setFrameSize:newSize2];
        
        // DO SPLIT
        
        [self.pdfKitSplitView addSubview: self.myPDFKitView2];
         [self.pdfKitSplitView adjustSubviews];
        
        // The second view holds the document only while the preview is split;
        // give it the document before its display parameters are set.
        [self.myPDFKitView2 setDocument:[self.myPDFKitView document]];
        // When the document was opened without a PDF, the second view did not start
        // watching its page then, so the page number box would not follow it (#14).
        [(MyPDFKitView *)self.myPDFKitView2 notificationSetup];
        
        // ADJUST DISPLAY PARAMETERS
        
        [(MyPDFKitView *)self.myPDFKitView2 setPageStyle:[(MyPDFKitView *)self.myPDFKitView pageStyle]];
        [(MyPDFKitView *)self.myPDFKitView2 setFirstPageStyle:[(MyPDFKitView *)self.myPDFKitView firstPageStyle]];
        if ( [(MyPDFKitView *)self.myPDFKitView resizeOption] == NEW_PDF_FIT_TO_NONE)
          [(MyPDFKitView *)self.myPDFKitView2 setMagnification: [(MyPDFKitView *)self.myPDFKitView magnification]];
        else {
            [(MyPDFKitView *)self.myPDFKitView2 setResizeOption:[(MyPDFKitView *)self.myPDFKitView resizeOption]];
            [(MyPDFKitView *)self.myPDFKitView2 setupMagnificationStyle];
            }
        [(MyPDFKitView *)self.myPDFKitView2 setupPageStyle];

        [(MyPDFKitView *)self.myPDFKitView2 moveSplitToCorrectSpot:[(MyPDFKitView *)self.myPDFKitView index]];
    }

    else
    { //THIS UNSPLITS THE WINDOW
        
        if (self.horizontal)
            {
                theFrame1 = [self.myPDFKitView frame];
                theFrame2 = [self.myPDFKitView2 frame];
                temp1 = theFrame1.size.height;
                temp2 = theFrame2.size.height;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalSplitSaved = YES;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight1 = temp1;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight2 = temp2;
            }
        else
            {
                theFrame1 = [self.myPDFKitView frame];
                theFrame2 = [self.myPDFKitView2 frame];
                temp1 = theFrame1.size.width;
                temp2 = theFrame2.size.width;
                ((MyPDFKitView *)self.myPDFKitView2).verticalSplitSaved = YES;
                ((MyPDFKitView *)self.myPDFKitView2).verticalWidth1 = temp1;
                ((MyPDFKitView *)self.myPDFKitView2).verticalWidth2 = temp2;
             }
        // The pane that stays shows the pinned popup of the pane that goes away, at the same
        // place on the screen, unless it has one of its own (#14).
        if (! [(MyPDFKitView *)self.myPDFKitView hasPinnedLinkPreview])
            movedPreview = [(MyPDFKitView *)self.myPDFKitView2 detachPinnedLinkPreviewWithWindowFrame: &movedPreviewFrame];
        [self.myPDFKitView2 removeFromSuperview];
        theFrame = [self.myPDFKitView frame];
        theSize.width = theFrame.size.width;
        theSize.height = self.frame.size.height;
        [self.myPDFKitView setFrameSize:theSize];
    }
  
 // ADJUST SCROLLING OF SPLIT OR UNSPLIT WINDOW
    
    // Let the split view give the panes their final sizes first, so that no later
    // layout moves the places put back below.
    [self.pdfKitSplitView adjustSubviews];
    [self.pdfKitSplitView layoutSubtreeIfNeeded];
    TSPreviewPaneRestore(firstView, firstTop);
    if (self.windowIsSplit)
        {
            if (secondView.locationSaved)
                [secondView restoreLocation];
            // Shift-split: the second pane shows the same place as the first.
            if (topToBottom)
                TSPreviewPaneRestore(secondView, firstTop);
        }
    
    // Otherwise each reload would replace the shared document's rendering
    // properties while PDFKit draws it in the first view.
    if (! self.windowIsSplit)
        [self.myPDFKitView2 setDocument:nil];
    
    if (movedPreview)
        [(MyPDFKitView *)self.myPDFKitView attachPinnedLinkPreview: movedPreview windowFrame: movedPreviewFrame];
    [self keepPinnedLinkPreviewsInView];
}





- (void) splitPdfKitWindow: (id)sender
{

if (! self.windowIsSplit)
        {
            BOOL sideBySide = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
            // A customized shortcut must retain the orientation of its menu command.
            if ([sender isKindOfClass:[NSMenuItem class]] &&
                [[sender identifier] hasPrefix:@"TSShortcut.splitWindow:."])
                sideBySide = [[sender identifier] isEqualToString:@"TSShortcut.splitWindow:.vertical"];
            if (sideBySide)
                {
                    [self.pdfKitSplitView setVertical:YES];
                    self.horizontal = NO;
                }
            else
                {
                    [self.pdfKitSplitView setVertical: NO];
                    self.horizontal = YES;
                }
        }
  
    [self mainSplitPdfKitWindow];
    TSSplitToggleItemsFollowSplit();

}

// Procedure called by menu item which splits both source and preview windows
- (void) splitWindow: (id)sender
{
	[self splitPdfKitWindow: sender];
}

- (void) fixAfterRotation: (BOOL) clockwise
{
	if (clockwise)
		[(MyPDFKitView *)self.myPDFKitView rotateClockwisePrimary];
	else
		[(MyPDFKitView *)self.myPDFKitView rotateCounterclockwisePrimary];
	[self.myPDFKitView layoutDocumentView];
	[self.myPDFKitView2 layoutDocumentView];
}

// Among other times, this is called by TSDocument at nib initialization time
/*
- (void) setActiveView:(PDFView *)theView
{
	
	if (self.activeView) {
		[(MyPDFKitView *)self.activeView setDrawMark: NO];
		[self.activeView display];
		}
	self.activeView = theView;
}

- (PDFView *)activeView;
{
	if (activeView == nil)
		activeView = myPDFKitView;
	return activeView;
}
*/

- (void) changeMouseMode: sender
{
	[(MyPDFKitView *)self.myPDFKitView changeMouseMode: sender];
	[(MyPDFKitView *)self.myPDFKitView2 changeMouseMode: sender];
}

- (void) doStepper: sender;
{
		[(MyPDFKitView *)self.activeView doStepper: sender];
}

- (void) changeScale: sender;
{
	[(MyPDFKitView *)self.activeView changeScale: sender];
}

- (void) goToKitPage: sender
{
	[(MyPDFKitView *)self.activeView goToKitPage: sender];
}


- (void) doFind: sender
{
  //  [self makeFirstResponder: [self.myDocument pdfKitSearchField]];
}


- (IBAction) takeDestinationFromOutline: (id) sender
{
	[(MyPDFKitView *)self.activeView takeDestinationFromOutline: sender];
}

- (IBAction)convertTiff:(id)sender
{
    [(TSDocument *)self.myDocument convertTiff:sender];
}

/*
- (BOOL)windowIsSplit
{
    return self.windowIsSplit;
}
*/


@end
