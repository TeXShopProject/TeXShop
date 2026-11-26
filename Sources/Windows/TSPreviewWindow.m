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

#import "TSDocumentWindowGlass.h"
#import "UseMitsu.h"

#import <AppKit/AppKit.h>
#import "TSPreviewWindow.h"
#import "TSDocument.h"
#import "MyPDFView.h"
#import "MyPDFKitView.h"
#import "globals.h"
#import "TSPreviewSplitDivider.h"
#import "TSToolbarController.h"
#import "TSPreviewTitlePathMenu.h"

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

	// The window background follows Light and Dark Mode.
	backColor = [NSColor windowBackgroundColor];
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
            // Below the toolbar when the content runs under it.
            [line.topAnchor constraintEqualToAnchor: view.safeAreaLayoutGuide.topAnchor],
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
    [theDocument annotationWindowWillClose: self];
    
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
	[self.myDocument refreshPreviewTitle];
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

    NSEvent *titleEvent = TSPreviewTitlePathMenuEvent(self, theEvent);
    if (titleEvent) {
        [super sendEvent:titleEvent];
        return;
    }
    


	// A dead key, such as ^ on a French keyboard, gives no characters.
	if ([self.myDocument fromKit] && ([theEvent type] == NSEventTypeKeyDown) && ([theEvent modifierFlags] & NSEventModifierFlagCommand) && [[theEvent characters] length] > 0) {
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
          // The part of the Preview under the title bar and the toolbar is theirs: a click there
          // goes to the toolbar, not to the magnifying glass (#44).
          NSRect Inside = TSDocumentWindowRectBelowToolbar(aView, aView.bounds);
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

		// A dead key gives no characters; such a key goes on to the window as any other.
		if ([theEvent type] == NSEventTypeKeyDown && [[theEvent characters] length] > 0) {

			/*
			if (([theEvent modifierFlags] & NSEventModifierFlagControl) &&
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
					if (([theEvent modifierFlags] & NSEventModifierFlagShift) == 0)
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
															  styleMask: NSWindowStyleMaskBorderless | NSWindowStyleMaskUtilityWindow
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

// Preview > Show Annotation Toolbar / Hide Annotation Toolbar, also while no part of the Preview is focused.
- (void)displayChoicesPanel:(id)sender
{
    [self.myDocument displayChoicesPanel: sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    if (anItem.action == @selector(displayChoicesPanel:))
        return [self.myDocument validateAnnotationBarItem: anItem];
    
	if ([anItem action] == @selector(splitWindow:)) {
		if (self.windowIsSplit)
			[anItem setState:NSControlStateValueOn];
		else
			[anItem setState:NSControlStateValueOff];
		return YES;
	}
    
    if ([anItem action] == @selector(toggleLinkPopups:)) {
        if (self.myDocument)
            return [self.myDocument validateMenuItem:anItem];
        MyPDFKitView *aView;
        aView = (MyPDFKitView *)self.myPDFKitView;
        
        if (aView.skipLinks)
            [anItem setState:NSControlStateValueOff];
        else
            [anItem setState:NSControlStateValueOn];
        return YES;
    }
    
    /*
    if ([anItem action] == @selector(toggleAnnotationMenu:)) {
        MyPDFKitView *aView;
        aView = (MyPDFKitView *)self.myPDFKitView;
        
        if (aView.useAnnotationMenu)
            [anItem setState:NSControlStateValueOn];
        else
            [anItem setState:NSControlStateValueOff];
        
        return YES;
    }
    */

	// The magnification of the active part.
	if ([anItem action] == @selector(changePDFViewSize:) && [self.myDocument fromKit])
		[anItem setState:[anItem tag] == [(MyPDFKitView *)[self.myDocument pdfKitView] resizeOption] ? NSControlStateValueOn : NSControlStateValueOff];
	if ([anItem action] == @selector(zoomToContent:) || [anItem action] == @selector(zoomToContentWidth:))
		return [self.myDocument fromKit] && [[[self.myDocument pdfKitView] document] pageCount] > 0;

	if ([anItem action] == sel_getUid("displayLatexPanel:"))
		return NO;
	if ([anItem action] == sel_getUid("displayMatrixPanel:"))
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
			[anItem action] == sel_getUid("doContext:") ||
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

	// The Preview window itself, when the PDF view is not the first responder.
	// The source window does not come through here.
	if ([anItem action] == @selector(performFindPanelAction:)) {
		MyPDFKitView *view = (MyPDFKitView *)self.myPDFKitView;
		if ([view isKindOfClass:[MyPDFKitView class]])
			return [view validateMenuItem:anItem];
		return NO;
	}

	return [super validateMenuItem: anItem];
}

- (void)performFindPanelAction:(id)sender
{
	MyPDFKitView *view = (MyPDFKitView *)self.activeView;
	if (![view isKindOfClass:[MyPDFKitView class]])
		view = (MyPDFKitView *)self.myPDFKitView;
	[view performFindPanelAction:sender];
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

- (void)zoomToContent: (id)sender
{
	if ([self.myDocument fromKit])
		[(MyPDFKitView *)[self.myDocument pdfKitView] zoomToContent: sender];
}

- (void)zoomToContentWidth: (id)sender
{
	if ([self.myDocument fromKit])
		[(MyPDFKitView *)[self.myDocument pdfKitView] zoomToContentWidth: sender];
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


- (void)switchViews
{
    if (self.windowIsSplit)
        [self switchSplitParts];
    else
        // The window that is not split shows one of two views, each with its own place,
        // display format, magnification and pinned popup (#60).
        [(MyPDFKitView *)self.myPDFKitView switchToOtherView];
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
    NSRect upperPopupFrame = NSZeroRect, lowerPopupFrame = NSZeroRect;
    TSLinkPreviewView *upperPopup = [upperView detachPinnedLinkPreviewWithWindowFrame: &upperPopupFrame];
    TSLinkPreviewView *lowerPopup = [lowerView detachPinnedLinkPreviewWithWindowFrame: &lowerPopupFrame];
    // Each popup goes to the same place on its page in the other part (#66).
    TSPopupPlace upperPopupPlace = TSPopupPlaceOnPage(upperView, upperPopupFrame);
    TSPopupPlace lowerPopupPlace = TSPopupPlaceOnPage(lowerView, lowerPopupFrame);
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
        else if (resizes[i] == NEW_PDF_FIT_TO_CONTENT_WIDTH)
            // Fitted to the size of the part it now has, after its place is put back below.
            [view setAutoScales:NO];
        else {
            [view setAutoScales:NO];
            [view setMagnification:scales[i]];
        }
    }
    [upperView setCurrentSelection:lowerSelection];
    [lowerView setCurrentSelection:upperSelection];

    TSPreviewPaneRestore(upperView, lower);
    TSPreviewPaneRestore(lowerView, upper);
    [upperView fitContentWidth];
    [lowerView fitContentWidth];

    // A pinned popup stays at its place on its page, in the part that now shows its page, also
    // at the end of the document, where the part cannot scroll as far, and at a magnification
    // that fits the page to the part. It is not brought into view, even when the part it comes
    // to is smaller, so that switching again gives back the first arrangement (#66).
    if (lowerPopup)
        [upperView placePinnedLinkPreview:lowerPopup windowFrame:TSPopupFrameInView(upperView, lowerPopupPlace, lowerPopupFrame)];
    if (upperPopup)
        [lowerView placePinnedLinkPreview:upperPopup windowFrame:TSPopupFrameInView(lowerView, upperPopupPlace, upperPopupFrame)];

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

    // The other part goes to another place: its pinned popup stays on its page, as when a link
    // is followed, and that of the part with the link stays where it is (#31, #35).
    [otherView cleanupMarqueeKeepingPinnedLinkPreview];
    [otherView keepPinnedLinkPreviewThroughMove];
    [otherView goToDestination: destination];
    // The divider may have widened the other part just before: its text from then is not
    // brought back once the views are laid out (#53).
    TSPreviewPlaceChosenByProgram(otherView);

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
        [self.activeView becomeFirstResponder];
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

// When PDFKit shows the password field of a locked PDF, it places the view by constraints
// instead of by its frame, and it leaves the view so after the PDF is unlocked. Splitting
// then gave the first part no size, and the window stayed blank after unsplitting (#55).
// The parts of a split are placed by their frames.
static void TSPreviewPlacePartByFrame(NSView *part)
{
    if (part.translatesAutoresizingMaskIntoConstraints)
        return;
    // The constraints the split view placed the part with would hold it, and the window, at
    // their size.
    NSMutableArray<NSLayoutConstraint *> *placing = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in part.superview.constraints)
        if (constraint.firstItem == part || constraint.secondItem == part)
            [placing addObject: constraint];
    [NSLayoutConstraint deactivateConstraints: placing];
    part.translatesAutoresizingMaskIntoConstraints = YES;
}

- (void) mainSplitPdfKitWindow
{
    NSSize        theSize, newSize1, newSize2;
    NSRect        theFrame, theFrame1, theFrame2;
    double      temp1, temp2;
    BOOL        splitInMiddle;
    BOOL        topToBottom;
    
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
    
    TSPreviewPlacePartByFrame(firstView);
    TSPreviewPlacePartByFrame(secondView);
    
    // Unsplitting keeps the part that was in use: the active part, unless nothing of it can be
    // seen, as when the divider has been dragged to the edge of the window; then the part that
    // can be seen stays. When that is the second part, the parts first change places with
    // everything they show, so the first view, which stays, shows what the second part showed,
    // with its pinned link popup by its link (#52). The parts keep their sizes for the next split.
    NSRect firstFrameBefore = [firstView frame], secondFrameBefore = [secondView frame];
    BOOL keepsSecondPart = NO;
    if (self.windowIsSplit) {
        BOOL firstSeen = TSPreviewPaneCapture(firstView).valid, secondSeen = TSPreviewPaneCapture(secondView).valid;
        keepsSecondPart = secondSeen && (self.activeView == secondView || ! firstSeen);
    }
    // Pages one below the other in a bottom part that stays: they stay where they are on the
    // screen, and the window shows above them what comes before them, as the top part that
    // stays shows what comes after it (#66).
    // The place is taken before the parts change places: Fit to Content Width fits the part
    // again after the switch and may then show it a little elsewhere.
    BOOL staysBelow = keepsSecondPart && self.horizontal &&
        (secondView.displayMode == kPDFDisplaySinglePageContinuous || secondView.displayMode == kPDFDisplayTwoUpContinuous);
    TSPreviewPanePlace secondTop = TSPreviewPaneCapture(secondView);
    NSPoint secondEdge = TSPreviewPaneWindowEdge(secondView);
    CGFloat secondScale = secondView.scaleFactor;
    if (keepsSecondPart)
        [self switchSplitParts];
    
// SAVE CURRENT LOCATIONS FOR LATER RESTORE
    
    // The first pane keeps the place at its top edge where it is on the screen (#23).
    TSPreviewPanePlace firstTop = TSPreviewPaneCapture(firstView);
    
    // The second pane shows the same place again when the window is split next time.
    if (self.windowIsSplit)
        {
            [secondView saveLocation];
            secondView.locationSaved = YES;
        }
    
    
    // Pages one below the other, split into a top and a bottom part for the first time, or
    // with Shift: nothing moves on the screen. The divider comes over the pages, the bottom
    // part shows what was below it, and a pinned popup stays where it is, now in both parts,
    // each with its own copy at the same place on its page (#66).
    BOOL continuesBelow = ! self.windowIsSplit && self.horizontal && firstTop.valid &&
        (firstView.displayMode == kPDFDisplaySinglePageContinuous || firstView.displayMode == kPDFDisplayTwoUpContinuous) &&
        (topToBottom || ! secondView.locationSaved);

// REVISE self.windowIsSplit FOR SPLITING, BUT DO NOT YET SPLIT
    
    
    [(MyPDFKitView *)self.myPDFKitView cleanupMarqueeKeepingPinnedLinkPreview];
    [(MyPDFKitView *)self.myPDFKitView2 cleanupMarqueeKeepingPinnedLinkPreview];
    
    
    if (self.windowIsSplit) {
        // The second part goes away: annotation text being edited for it is dropped.
        [self.myDocument annotationPartWillCollapse: self.myPDFKitView2];
        self.windowIsSplit = NO;
        self.activeView = self.myPDFKitView;
        [self.activeView becomeFirstResponder];
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
        // Side by side, the parts start below the toolbar before they are given their pages.
        [self placeSplitViewForToolbar];
        // In a window whose content runs under the toolbar, the parts share the area that can
        // be seen: the band under the toolbar is not counted, as when their heights were saved.
        if (self.horizontal && TSDocumentWindowHiddenTop(self.pdfKitSplitView) > 0) {
            if ((! splitInMiddle) && ((MyPDFKitView *)self.myPDFKitView2).horizontalSplitSaved)
                TSDocumentWindowSplitInShares(self.pdfKitSplitView, newSize1.height, newSize2.height);
            else
                TSDocumentWindowSplitEvenly(self.pdfKitSplitView);
        }
        
        // The second view holds the document only while the preview is split;
        // give it the document before its display parameters are set.
        [self.myPDFKitView2 setDocument:[self.myPDFKitView document]];
        // When the document was opened without a PDF, the second view did not start
        // watching its page then, so the page number box would not follow it (#14).
        [(MyPDFKitView *)self.myPDFKitView2 notificationSetup];
        
        // ADJUST DISPLAY PARAMETERS
        
        [(MyPDFKitView *)self.myPDFKitView2 setPageStyle:[(MyPDFKitView *)self.myPDFKitView pageStyle]];
        [(MyPDFKitView *)self.myPDFKitView2 setFirstPageStyle:[(MyPDFKitView *)self.myPDFKitView firstPageStyle]];
        // The display format comes first: Fit to Content Width fits the pages as they are laid out.
        [(MyPDFKitView *)self.myPDFKitView2 setupPageStyle];
        if ( [(MyPDFKitView *)self.myPDFKitView resizeOption] == NEW_PDF_FIT_TO_NONE)
          [(MyPDFKitView *)self.myPDFKitView2 setMagnification: [(MyPDFKitView *)self.myPDFKitView magnification]];
        else {
            [(MyPDFKitView *)self.myPDFKitView2 setResizeOption:[(MyPDFKitView *)self.myPDFKitView resizeOption]];
            [(MyPDFKitView *)self.myPDFKitView2 setupMagnificationStyle];
            }

        [(MyPDFKitView *)self.myPDFKitView2 moveSplitToCorrectSpot:[(MyPDFKitView *)self.myPDFKitView index]];
    }

    else
    { //THIS UNSPLITS THE WINDOW
        
        if (self.horizontal)
            {
                theFrame1 = keepsSecondPart ? firstFrameBefore : [self.myPDFKitView frame];
                theFrame2 = keepsSecondPart ? secondFrameBefore : [self.myPDFKitView2 frame];
                // The height that can be seen: the band under the toolbar is left out.
                temp1 = MAX(0, theFrame1.size.height - TSDocumentWindowHiddenTop(self.pdfKitSplitView));
                temp2 = theFrame2.size.height;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalSplitSaved = YES;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight1 = temp1;
                ((MyPDFKitView *)self.myPDFKitView2).horizontalHeight2 = temp2;
            }
        else
            {
                theFrame1 = keepsSecondPart ? firstFrameBefore : [self.myPDFKitView frame];
                theFrame2 = keepsSecondPart ? secondFrameBefore : [self.myPDFKitView2 frame];
                temp1 = theFrame1.size.width;
                temp2 = theFrame2.size.width;
                ((MyPDFKitView *)self.myPDFKitView2).verticalSplitSaved = YES;
                ((MyPDFKitView *)self.myPDFKitView2).verticalWidth1 = temp1;
                ((MyPDFKitView *)self.myPDFKitView2).verticalWidth2 = temp2;
             }
        // The part that goes away takes its pinned link popup with it: in the part that stays
        // it would float over pages its link is not on (#52).
        [(MyPDFKitView *)self.myPDFKitView2 detachPinnedLinkPreviewWithWindowFrame: NULL];
        [self.myPDFKitView2 removeFromSuperview];
        // The part that stays runs under the toolbar again.
        [self placeSplitViewForToolbar];
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
    // Only at the same magnification: a magnification that fits the page to the height of the
    // window enlarges the pages, which then start at the top of the window.
    if (staysBelow && fabs(firstView.scaleFactor - secondScale) < 1e-6)
        TSPreviewPaneRestoreAt(firstView, secondTop, secondEdge);
    else
        TSPreviewPaneRestore(firstView, firstTop);
    if (self.windowIsSplit && continuesBelow)
        {
            // The first pane shows its top where it was, at the same magnification, so the
            // pages go on below it as they were laid out before the split.
            TSPreviewPaneRestore(secondView, TSPreviewPaneCaptureAt(firstView, TSPreviewPaneWindowEdge(secondView)));
            [secondView showCopyOfPinnedLinkPreviewOfView: firstView];
        }
    else if (self.windowIsSplit)
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
    
    // The popups stay at their places on their pages, also out of view.
    if (! continuesBelow)
        [self keepPinnedLinkPreviewsInView];
}





// In a window whose content runs under the title bar and the toolbar (macOS 26 and later),
// parts side by side start below the toolbar. Running under it, each part brings its own
// band under the toolbar, AppKit blurs only one of them, and the divider runs up through
// the toolbar. The Preview window is full-size on macOS 26 and later, so side-by-side parts
// start below its toolbar too. A single part, and parts one above the other, fill the
// content view and run under the toolbar. Earlier systems are not full-size, so this
// placement is unused and the content view already starts below the toolbar. The split
// view follows the band when it changes height, as when the annotation toolbar is shown
// or in full screen.
// The frame the split view gets back when its parts stop being side by side: the content view's
// bounds with the outsets it had before they went side by side (in the nib, 2 points below the
// bottom edge).
- (void) fitSplitViewToContent
{
    NSSplitView *split = self.pdfKitSplitView;
    if (split.superview != self.contentView || self.splitViewPlacement != nil)
        return;
    NSRect bounds = self.contentView.bounds;
    NSEdgeInsets outsets = self.splitViewOutsets;
    split.frame = NSMakeRect(NSMinX(bounds) - outsets.left, NSMinY(bounds) - outsets.bottom,
                             NSWidth(bounds) + outsets.left + outsets.right, NSHeight(bounds) + outsets.top + outsets.bottom);
}

- (void) placeSplitViewForToolbar
{
    NSSplitView *split = self.pdfKitSplitView;
    NSView *content = self.contentView;
    BOOL here = split != nil && split.superview == content;
    BOOL below = here && (self.styleMask & NSWindowStyleMaskFullSizeContentView) && self.windowIsSplit && split.isVertical;
    if (! below) {
        [self releaseSplitViewPlacement];
        // In this window with one part, or parts one above the other: the next split side by side
        // starts from the frame the split view then has, as in RC1.
        if (here)
            self.splitViewOutsetsTaken = NO;
        return;
    }
    if (self.splitViewPlacement != nil)
        return;
    // How far the frame reaches beyond the content view when the parts first go side by side. A
    // move into the combined window and back with the parts side by side keeps it, so they keep
    // reaching so far at the sides and the bottom, and get that frame back when unsplit.
    if (! self.splitViewOutsetsTaken) {
        NSRect frame = split.frame, bounds = content.bounds;
        self.splitViewOutsets = NSEdgeInsetsMake(NSMaxY(frame) - NSMaxY(bounds), NSMinX(bounds) - NSMinX(frame),
                                                 NSMinY(bounds) - NSMinY(frame), NSMaxX(frame) - NSMaxX(bounds));
        self.splitViewOutsetsTaken = YES;
    }
    split.translatesAutoresizingMaskIntoConstraints = NO;
    // Below the band; at the sides and the bottom as before.
    NSEdgeInsets outsets = self.splitViewOutsets;
    self.splitViewPlacement = @[
        [split.topAnchor constraintEqualToAnchor: content.safeAreaLayoutGuide.topAnchor],
        [split.leadingAnchor constraintEqualToAnchor: content.leadingAnchor constant: -outsets.left],
        [split.trailingAnchor constraintEqualToAnchor: content.trailingAnchor constant: outsets.right],
        [split.bottomAnchor constraintEqualToAnchor: content.bottomAnchor constant: outsets.bottom]];
    [NSLayoutConstraint activateConstraints: self.splitViewPlacement];
    [content layoutSubtreeIfNeeded];
}

- (void) releaseSplitViewPlacement
{
    if (self.splitViewPlacement == nil)
        return;
    [NSLayoutConstraint deactivateConstraints: self.splitViewPlacement];
    self.splitViewPlacement = nil;
    self.pdfKitSplitView.translatesAutoresizingMaskIntoConstraints = YES;
    [self fitSplitViewToContent];
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
	// Turned pages have other widths.
	[(MyPDFKitView *)self.myPDFKitView fitContentWidth];
	[(MyPDFKitView *)self.myPDFKitView2 fitContentWidth];
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



#pragma mark - The Preview on the next launch (#71)

NSUserInterfaceItemIdentifier const TSPreviewWindowRestorationIdentifier = @"TSPreviewWindowOfPDF";
static NSString *const TSPreviewRestorationBookmarkKey = @"TSPreviewDocumentBookmark";
static NSString *const TSPreviewRestorationURLKey = @"TSPreviewDocumentURL";
static NSString *const TSPreviewRestorationFrameKey = @"TSPreviewWindowFrame";
static NSString *const TSPreviewRestorationDrawerKey = @"TSPreviewDrawerOpen";

// A choice of the Two-Page Arrangement menu: -1 when the document's own is used.
static NSInteger TSPreviewOverrideCode(NSNumber *value)
{
    return value ? (value.boolValue ? 1 : 0) : -1;
}

static NSNumber *TSPreviewOverrideValue(NSInteger code)
{
    return code < 0 ? nil : @(code == 1);
}

- (void)encodePreviewStateWithCoder:(NSCoder *)coder
{
    MyPDFKitView *first = (MyPDFKitView *)self.myPDFKitView, *second = (MyPDFKitView *)self.myPDFKitView2;
    if (![[first document] pageCount]) return;
    [first encodePreviewStateWithCoder:coder prefix:@"TSPreviewFirst"];
    [coder encodeInteger:[first previewRotation] forKey:@"TSPreviewRotation"];
    [coder encodeInteger:TSPreviewOverrideCode(self.myDocument.previewDirectionOverride) forKey:@"TSPreviewDirection"];
    [coder encodeInteger:TSPreviewOverrideCode(self.myDocument.previewBookOverride) forKey:@"TSPreviewBook"];
    NSSplitView *splitView = self.pdfKitSplitView;
    BOOL split = self.windowIsSplit && second && splitView.subviews.count >= 2;
    [coder encodeBool:split forKey:@"TSPreviewSplit"];
    if (!split) return;
    [coder encodeBool:self.horizontal forKey:@"TSPreviewSplitHorizontal"];
    // The share of the first part, so that the divider keeps its place in a window of another size;
    // 0 and 1 when it was pushed to an end.
    NSRect a = splitView.subviews[0].frame, b = splitView.subviews[1].frame;
    CGFloat one = splitView.isVertical ? NSWidth(a) : NSHeight(a);
    CGFloat two = splitView.isVertical ? NSWidth(b) : NSHeight(b);
    if (one + two > 0)
        [coder encodeDouble:one / (one + two) forKey:@"TSPreviewSplitShare"];
    [coder encodeBool:self.activeView == second forKey:@"TSPreviewSecondInUse"];
    [second encodePreviewStateWithCoder:coder prefix:@"TSPreviewSecond"];
}

- (BOOL)restorePreviewStateWithCoder:(NSCoder *)coder
{
    MyPDFKitView *first = (MyPDFKitView *)self.myPDFKitView, *second = (MyPDFKitView *)self.myPDFKitView2;
    if (![[first document] pageCount] || ![coder containsValueForKey:@"TSPreviewFirstPageStyle"]) return NO;

    TSDocument *document = self.myDocument;
    if ([coder containsValueForKey:@"TSPreviewDirection"]) {
        document.previewDirectionOverride = TSPreviewOverrideValue([coder decodeIntegerForKey:@"TSPreviewDirection"]);
        document.previewBookOverride = TSPreviewOverrideValue([coder decodeIntegerForKey:@"TSPreviewBook"]);
        [first applyPreviewArrangement];
        [second applyPreviewArrangement];
    }
    // The pages turned as they were, before any place on them is put back.
    if ([coder containsValueForKey:@"TSPreviewRotation"])
        [first restorePreviewRotation:[coder decodeIntegerForKey:@"TSPreviewRotation"]];
    [first restorePreviewDisplayWithCoder:coder prefix:@"TSPreviewFirst"];
    BOOL secondRestoring = NO, secondInUse = NO;
    if ([coder decodeBoolForKey:@"TSPreviewSplit"] && second) {
        if (!self.windowIsSplit) {
            BOOL horizontal = [coder decodeBoolForKey:@"TSPreviewSplitHorizontal"];
            [self.pdfKitSplitView setVertical:!horizontal];
            self.horizontal = horizontal;
            [self mainSplitPdfKitWindow];
            TSSplitToggleItemsFollowSplit();
        }
        NSSplitView *splitView = self.pdfKitSplitView;
        if (self.windowIsSplit && splitView.subviews.count >= 2) {
            double share = [coder decodeDoubleForKey:@"TSPreviewSplitShare"];
            if ([coder containsValueForKey:@"TSPreviewSplitShare"] && share >= 0 && share <= 1) {
                CGFloat whole = (splitView.isVertical ? NSWidth(splitView.bounds) : NSHeight(splitView.bounds)) - splitView.dividerThickness;
                [splitView setPosition:round(whole * share) ofDividerAtIndex:0];
                [splitView adjustSubviews];
            }
            secondRestoring = [second restorePreviewDisplayWithCoder:coder prefix:@"TSPreviewSecond"];
            [second layoutDocumentView];
            secondInUse = [coder decodeBoolForKey:@"TSPreviewSecondInUse"];
        }
    }
    // The places and pinned popups are put back once the window and its parts are laid out.
    __weak TSPreviewWindow *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TSPreviewWindow *window = weakSelf;
        if (!window) return;
        [window layoutIfNeeded];
        MyPDFKitView *one = (MyPDFKitView *)window.myPDFKitView, *two = (MyPDFKitView *)window.myPDFKitView2;
        [one finishRestoringPreview];
        if (window.windowIsSplit) {
            if (secondRestoring)
                [two finishRestoringPreview];
            [(secondInUse ? two : one) becomeActiveView];
            [window showActivePart];
        }
        [window.myDocument updatePreviewLayoutControls];
    });
    return YES;
}

// The state of a source's Preview is kept with the source: whatever renews the window's state
// renews the document's as well.
- (void)invalidateRestorableState
{
    static BOOL forwarding = NO;
    [super invalidateRestorableState];
    if (forwarding) return;
    forwarding = YES;
    [self.myDocument invalidateRestorableState];
    forwarding = NO;
}

// The Preview window of a PDF opened by itself is the PDF's only window: macOS keeps it, with the
// file it shows, and opens the file again on the next launch.
- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
    NSURL *url = self.myDocument.fileURL;
    if (self.restorationClass != [TSPreviewWindow class] || !url.isFileURL) return;
    NSData *bookmark = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
    if (bookmark)
        [coder encodeObject:bookmark forKey:TSPreviewRestorationBookmarkKey];
    [coder encodeObject:url forKey:TSPreviewRestorationURLKey];
    [coder encodeObject:[self stringWithSavedFrame] forKey:TSPreviewRestorationFrameKey];
    // Whether the outline drawer was out (a source keeps this in its own state).
    NSInteger drawerState = [[(MyPDFKitView *)self.myPDFKitView drawer] state];
    [coder encodeBool:(drawerState == NSDrawerOpenState || drawerState == NSDrawerOpeningState)
               forKey:TSPreviewRestorationDrawerKey];
    [self encodePreviewStateWithCoder:coder];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
    [super restoreStateWithCoder:coder];
    if (self.restorationClass != [TSPreviewWindow class])
        return;
    // The window was placed by the settings for Preview windows when the PDF was opened.
    NSString *frame = [coder decodeObjectOfClass:[NSString class] forKey:TSPreviewRestorationFrameKey];
    if (frame.length)
        [self setFrameFromString:frame];
    if ([coder containsValueForKey:TSPreviewRestorationDrawerKey]) {
        NSDrawer *drawer = [(MyPDFKitView *)self.myPDFKitView drawer];
        if ([coder decodeBoolForKey:TSPreviewRestorationDrawerKey])
            [drawer open];
        else
            [drawer close];
    }
    [self restorePreviewStateWithCoder:coder];
}

+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler
{
    NSURL *url = nil;
    NSData *bookmark = [state decodeObjectOfClass:[NSData class] forKey:TSPreviewRestorationBookmarkKey];
    if (bookmark) {
        BOOL stale = NO;
        // The bookmark finds the file also after it was moved or renamed.
        url = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithoutUI
                                  relativeToURL:nil bookmarkDataIsStale:&stale error:NULL];
    }
    if (!url)
        url = [state decodeObjectOfClass:[NSURL class] forKey:TSPreviewRestorationURLKey];
    if (![identifier isEqualToString:TSPreviewWindowRestorationIdentifier] || !url.isFileURL) {
        completionHandler(nil, nil);
        return;
    }
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES
        completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
            TSDocument *opened = [document isKindOfClass:[TSDocument class]] ? (TSDocument *)document : nil;
            completionHandler(opened.skipTextWindow ? opened.pdfKitWindow : nil, error);
        }];
}

@end
