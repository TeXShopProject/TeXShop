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
 * $Id: TSLaTeXPanelController.m 254 2007-06-03 21:09:25Z fingolfin $
 *
 * Created by lenglin on Sun Aug 26 2001.
 *
 */

#import "TSLaTeXPanelController.h"
#import "TSLibraryRepair.h"
#import "globals.h"
#import <objc/runtime.h>

// The buttons of the panel: a frame with rounded corners as large as the button, filled under the pointer
// and when pressed, or drawn as a thin outline all the time when LPanelOutlines is NO. The buttons come from
// the compiled panels as NSButtonCell; they become this class, which adds no storage.
@interface TSLaTeXPanelButtonCell : NSButtonCell
@end

@implementation TSLaTeXPanelButtonCell

- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView
{
	NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 0.5, 0.5) xRadius:6 yRadius:6];
	// AppKit asks for the frame of a button that shows it only under the pointer when the pointer is over it.
	if ([self isHighlighted] || [self showsBorderOnlyWhileMouseInside]) {
		[([self isHighlighted] ? [NSColor tertiaryLabelColor] : [NSColor quaternaryLabelColor]) setFill];
		[shape fill];
	} else {
		[[NSColor separatorColor] setStroke];
		[shape setLineWidth:1];
		[shape stroke];
	}
}

@end

@interface TSLaTeXPanelController ()
// The two groups of buttons: symbols above, environments below. Each shows the page chosen with the
// segmented control above it.
@property (strong) NSArray<NSTabView *> *buttonPages;
@property (strong) NSArray<NSSegmentedControl *> *pageChoosers;
@end

// A picture of a symbol, drawn in black and shades of gray with no transparency, as ink in the color of
// text: black in light appearance, white in dark. Lighter gray is fainter ink, so the edges stay smooth.
static NSImage *TSInkImage(NSImage *image)
{
	CGImageRef picture = [image CGImageForProposedRect:NULL context:nil hints:nil];
	if (picture == NULL)
		return image;
	NSBitmapImageRep *source = [[NSBitmapImageRep alloc] initWithCGImage:picture];
	NSInteger width = [source pixelsWide], height = [source pixelsHigh];
	NSMutableData *coverage = [NSMutableData dataWithLength:width * height];
	unsigned char *bytes = [coverage mutableBytes];
	for (NSInteger y = 0; y < height; y++)
		for (NSInteger x = 0; x < width; x++) {
			NSColor *color = [[source colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace genericGrayColorSpace]];
			CGFloat ink = color == nil ? 0 : (1 - [color whiteComponent]) * [color alphaComponent];
			// A mask paints where it is dark.
			bytes[y * width + x] = (unsigned char)lround((1 - ink) * 255);
		}
	CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)coverage);
	// The drawing below keeps the mask.
	id mask = CFBridgingRelease(CGImageMaskCreate(width, height, 8, 8, width, provider, NULL, true));
	CGDataProviderRelease(provider);
	if (mask == nil)
		return image;
	NSImage *result = [NSImage imageWithSize:[image size] flipped:NO drawingHandler:^BOOL(NSRect rect) {
		CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
		CGContextSaveGState(context);
		CGContextClipToMask(context, NSRectToCGRect(rect), (__bridge CGImageRef)mask);
		[[NSColor textColor] setFill];
		NSRectFill(rect);
		CGContextRestoreGState(context);
		return YES;
	}];
	return result;
}

@implementation TSLaTeXPanelController

static id _sharedInstance = nil;

+ (id)sharedInstance
{
	if (_sharedInstance == nil)
	{
		_sharedInstance = [[TSLaTeXPanelController alloc] initWithWindowNibName:@"completionpanel1.2"];
	}
	return _sharedInstance;
}

- (id)init
{
	if ((self = [super init])) {
		shown = NO;
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
/*
	[arrayFunctions1 release];
	[arrayEnvironments release];
	[arrayTypeface release];
	[arrayGreek release];
	[arrayInternational release];
	[arrayMath release];
	[arraySymbols release];
	[arrayCustomized release];

	[super dealloc];
 */
}

- (void)windowDidLoad
{
	NSInteger			i;
	NSPoint		aPoint;
	NSString		*completionPath;
	NSDictionary	*completionDictionary;
	// added by G.K. (Georg Klein)
	NSInteger			aButtons;
	//

	NSBundle *myBundle=[NSBundle mainBundle];

	completionPath = [LatexPanelPath stringByStandardizingPath];
	completionPath = [completionPath stringByAppendingPathComponent:@"completion"];
	completionPath = [completionPath stringByAppendingPathExtension:@"plist"];
	if (TSLibraryRepairFile(completionPath, TSLibraryBundledPath(@"LatexPanel/completion.plist"), TSLibraryShapeOfBundledCheck()))
		completionDictionary=[NSDictionary dictionaryWithContentsOfFile:completionPath];
	else
		completionDictionary=[NSDictionary dictionaryWithContentsOfFile:
			TSLibraryBundledPath(@"LatexPanel/completion.plist") ?: @""];

	[super windowDidLoad];

	[[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(panelDidMove:)
												 name:NSWindowDidMoveNotification object:[self window]];
	[[NSNotificationCenter defaultCenter] addObserver: self selector:@selector(panelWillClose:)
												 name:NSWindowWillCloseNotification object:[self window]];

	// result = [[self window] setFrameAutosaveName:LatexPanelNameKey];
	aPoint.x = [[NSUserDefaults standardUserDefaults] floatForKey:PanelOriginXKey];
	aPoint.y = [[NSUserDefaults standardUserDefaults] floatForKey:PanelOriginYKey];
	[[self window] setFrameOrigin: aPoint];
	[[self window] setHidesOnDeactivate: YES];
	// [self window] is actually an NSPanel, so it responds to the message below
	[(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded: YES];

	arrayFunctions1=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"Functions1"]];
	arrayEnvironments=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"Environments" ]];
	arrayTypeface=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"Typeface" ]];
	arrayInternational=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"International" ]];
	arrayGreek=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"Greek" ]];
	arrayMath=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"Math" ]];
	arraySymbols=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"Symbols" ]];
	// added by G.K.
	arrayCustomized=[[NSArray alloc] initWithArray:[completionDictionary objectForKey:@"Customized" ]];
	// end add

	notifcenter=[NSNotificationCenter defaultCenter];
	if ([[NSUserDefaults standardUserDefaults] boolForKey:LPanelOutlinesKey]) {

		for (i=0;i<16;i++)
		{
			[[environbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
		}

		for (i=0;i<30;i++)
		{
			[[functionsbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
		}

		for (i=0;i<15;i++)
		{
			[[typefacebuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
		}

		for (i=0;i<55;i++)
		{
			[[mathbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
            // [[mathbuttonmatrix cellWithTag:i] image].template=YES;
		}

		for (i=0;i<55;i++)
		{
			[[symbolsbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
            // if (i > 10)  [[symbolsbuttonmatrix cellWithTag:i] image].template=YES;
		}

		for (i=0;i<30;i++)
		{
			[[greekbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
		}
		for (i=44;i<55;i++)
		{
			[[greekbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
		}

		for (i=0;i<35;i++)
		{
			[[intlbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
		}
		for (i=44;i<55;i++)
		{
			[[intlbuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:YES];
		}
	}

	// added by G.K.
	// The custom buttons have their names whether or not LPanelOutlines is NO.
	aButtons = [arrayCustomized count]/2;
	for (i=0;i<aButtons;i++) {
		[[custombuttonmatrix cellWithTag:i] setEnabled:YES];
		[[custombuttonmatrix cellWithTag:i] setBordered:YES];
		[[custombuttonmatrix cellWithTag:i] setTitle:[arrayCustomized objectAtIndex:(i*2)]];
		[[custombuttonmatrix cellWithTag:i] setShowsBorderOnlyWhileMouseInside:
			[[NSUserDefaults standardUserDefaults] boolForKey:LPanelOutlinesKey]];
	}
	[custombuttonmatrix setNeedsDisplay:YES];
	// end add

	// The pictures of the symbols follow the light or dark appearance.
	for (i=0;i<55;i++)
	{
		NSButtonCell *cell = [mathbuttonmatrix cellWithTag:i];
		if ([cell image] != nil)
			[cell setImage:TSInkImage([cell image])];
		cell = [symbolsbuttonmatrix cellWithTag:i];
		if (i > 10 && [cell image] != nil)
			[cell setImage:TSInkImage([cell image])];
	}

	[self arrangeControls];
}

- (IBAction)putenvironments:(id)sender
{
	[notifcenter postNotificationName:@"completionpanel" object:[arrayEnvironments objectAtIndex:[[sender selectedCell] tag]]];
}

- (IBAction)putfunctions1:(id)sender
{
	[notifcenter postNotificationName:@"completionpanel" object:[arrayFunctions1 objectAtIndex:[[sender selectedCell] tag]]];
}

- (IBAction)putgreek:(id)sender
{
	NSInteger i=[[sender selectedCell] tag];
	if (i>29)
		i=i-14;
	[notifcenter postNotificationName:@"completionpanel" object:[arrayGreek objectAtIndex:i]];
}

- (IBAction)putintl:(id)sender
{
	NSInteger i=[[sender selectedCell] tag];
	if (i>34)
		i=i-9;
	[notifcenter postNotificationName:@"completionpanel" object:[arrayInternational objectAtIndex:i]];
}

- (IBAction)putmath:(id)sender
{
	NSInteger i=[[sender selectedCell] tag];
	[notifcenter postNotificationName:@"completionpanel" object:[arrayMath objectAtIndex:i]];
}

- (IBAction)putsymbols:(id)sender
{
	NSInteger i=[[sender selectedCell] tag];
	[notifcenter postNotificationName:@"completionpanel" object:[arraySymbols objectAtIndex:i]];
}

- (IBAction)puttypeface:(id)sender
{
	[notifcenter postNotificationName:@"completionpanel" object:[arrayTypeface objectAtIndex:[[sender selectedCell] tag]]];
}

// added by G.K.
- (IBAction)putcustomized:(id)sender
{
	[notifcenter postNotificationName:@"completionpanel" object:[arrayCustomized objectAtIndex:([[sender selectedCell] tag]*2)+1]];
}
// end add

- (void)textWindowDidBecomeKey:(NSNotification *)note
{
    
	// if latex panel is hidden, show it
	if (shown)
    {
		[[self window] orderFront:self];
    }
}

- (void)pdfWindowDidBecomeKey:(NSNotification *)note
{
	// if latex panel is visible, hide it
	if (shown)
		[[self window] orderOut:self];
}

- (IBAction)showWindow:(id)sender
{
	shown = YES;
    
	[super showWindow:sender];
}

- (void)hideWindow:(id)sender
{
	shown = NO;
	[[self window] close];
}

- (void)panelWillClose:(NSNotification *)notification
{
        shown = NO;
        NSMenuItem *myItem = [[NSApp windowsMenu] itemWithTitle:NSLocalizedString(@"Close LaTeX Panel", @"Close LaTeX Panel")];
        [myItem  setTitle:NSLocalizedString(@"LaTeX Panel...", @"LaTeX Panel...")];
        [myItem setTag:0];
}

- (void)panelDidMove:(NSNotification *)notification
{
	NSRect	myFrame;
	CGFloat	x, y;

	myFrame = [[self window] frame];
	x = myFrame.origin.x; y = myFrame.origin.y;
	[[NSUserDefaults standardUserDefaults] setFloat:x forKey:PanelOriginXKey];
	[[NSUserDefaults standardUserDefaults] setFloat:y forKey:PanelOriginYKey];
	// [[self window] saveFrameUsingName:@"theLatexPanel"];
}

- (void)setIconTemplate:(BOOL)value
{
	// The pictures of the symbols are drawn in the color of text of the appearance in which they are shown
	// (TSInkImage), so they need no template in dark appearance.
}

#pragma mark Layout

static const CGFloat TSLaTeXPanelMargin = 20;

static NSRect TSUnionOfSubviews(NSView *view)
{
	NSRect all = NSZeroRect;
	for (NSView *subview in [view subviews])
		all = NSIsEmptyRect(all) ? [subview frame] : NSUnionRect(all, [subview frame]);
	return all;
}

// Choosing a page with the segmented control above it.
- (void)choosePage:(NSSegmentedControl *)sender
{
	NSUInteger index = [self.pageChoosers indexOfObject:sender];
	if (index != NSNotFound)
		[self.buttonPages[index] selectTabViewItemAtIndex:[sender selectedSegment]];
}

// The compiled panels of the localizations draw each group in a tab view with its own frame, and the buttons
// with words as text that is gray until the pointer is over it. The groups now have a segmented control
// above them and no frame.
- (void)arrangeControls
{
	NSWindow *window = [self window];
	NSView *content = [window contentView];
	NSMutableArray<NSTabView *> *pages = [NSMutableArray array];
	for (NSView *view in [content subviews])
		if ([view isKindOfClass:[NSTabView class]])
			[pages addObject:(NSTabView *)view];
	if ([pages count] != 2)
		return;
	// The symbols are above the environments.
	[pages sortUsingComparator:^NSComparisonResult(NSTabView *a, NSTabView *b) {
		return NSMaxY([a frame]) > NSMaxY([b frame]) ? NSOrderedAscending : NSOrderedDescending;
	}];

	// Every button, symbol or word, has no frame of its own: a frame with rounded corners shows under the
	// pointer (or all the time when LPanelOutlines is NO; TSLaTeXPanelButtonCell), and the symbols and words
	// are in the color of text, not in the gray AppKit gives a title whose frame is hidden. The buttons are a
	// little apart so that two frames never touch.
	NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
	[centered setAlignment:NSTextAlignmentCenter];
	// The words in the regular size of text, as in the segmented controls; each page of words as wide as its
	// widest word needs.
	NSArray<NSMatrix *> *words = @[functionsbuttonmatrix, environbuttonmatrix, typefacebuttonmatrix, custombuttonmatrix];
	NSFont *wordFont = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	for (NSMatrix *matrix in words) {
		CGFloat width = [matrix cellSize].width;
		for (NSButtonCell *cell in [matrix cells]) {
			[cell setFont:wordFont];
			width = MAX(width, ceil([[cell title] sizeWithAttributes:@{NSFontAttributeName: wordFont}].width) + 16);
		}
		[matrix setCellSize:NSMakeSize(width, [matrix cellSize].height)];
	}
	for (NSMatrix *matrix in @[mathbuttonmatrix, symbolsbuttonmatrix, greekbuttonmatrix, intlbuttonmatrix,
							   functionsbuttonmatrix, environbuttonmatrix, typefacebuttonmatrix, custombuttonmatrix]) {
		for (NSButtonCell *cell in [matrix cells]) {
			if ([cell class] == [NSButtonCell class])
				object_setClass(cell, [TSLaTeXPanelButtonCell class]);
			[cell setBezelStyle:NSBezelStyleToolbar];
			if ([[cell title] length])
				[cell setAttributedTitle:[[NSAttributedString alloc] initWithString:[cell title] attributes:@{
					NSFontAttributeName: [cell font] ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
					NSForegroundColorAttributeName: [NSColor labelColor], NSParagraphStyleAttributeName: centered}]];
		}
		[matrix setIntercellSpacing:NSMakeSize(4, 4)];
		[matrix sizeToCells];
	}

	// Each page as large as its largest group of buttons; the panel as wide as the widest page.
	NSMutableArray<NSSegmentedControl *> *choosers = [NSMutableArray array];
	NSMutableArray<NSValue *> *pageSizes = [NSMutableArray array];
	CGFloat width = 0;
	for (NSTabView *page in pages) {
		NSMutableArray<NSString *> *labels = [NSMutableArray array];
		NSSize size = NSZeroSize;
		for (NSTabViewItem *item in [page tabViewItems]) {
			[labels addObject:[item label]];
			NSRect group = TSUnionOfSubviews([item view]);
			size.width = MAX(size.width, NSWidth(group));
			size.height = MAX(size.height, NSHeight(group));
		}
		NSSegmentedControl *chooser = [NSSegmentedControl segmentedControlWithLabels:labels trackingMode:NSSegmentSwitchTrackingSelectOne
																			   target:self action:@selector(choosePage:)];
		[chooser sizeToFit];
		[chooser setAutoresizingMask:NSViewNotSizable];
		[choosers addObject:chooser];
		[pageSizes addObject:[NSValue valueWithSize:size]];
		width = MAX(width, MAX(size.width, NSWidth([chooser frame])));
	}
	// The groups keep their sizes when their pages change size below.
	for (NSTabView *page in pages)
		for (NSTabViewItem *item in [page tabViewItems])
			for (NSView *group in [[item view] subviews])
				[group setAutoresizingMask:NSViewNotSizable];
	const CGFloat margin = TSLaTeXPanelMargin;
	CGFloat height = margin;
	for (NSUInteger i = 0; i < [pages count]; i++)
		height += NSHeight([choosers[i] frame]) + 12 + [pageSizes[i] sizeValue].height + margin;
	[window setContentSize:NSMakeSize(ceil(width + 2 * margin), ceil(height))];

	CGFloat top = NSHeight([content bounds]) - margin;
	for (NSUInteger i = 0; i < [pages count]; i++) {
		NSTabView *page = pages[i];
		NSSegmentedControl *chooser = choosers[i];
		NSSize size = [pageSizes[i] sizeValue];
		NSRect frame = [chooser frame];
		frame.origin = NSMakePoint(round((NSWidth([content bounds]) - NSWidth(frame)) / 2), top - NSHeight(frame));
		[chooser setFrame:frame];
		[content addSubview:chooser];
		top = NSMinY(frame) - 12;
		[page setTabViewType:NSNoTabsNoBorder];
		[page setAutoresizingMask:NSViewNotSizable];
		[page setFrame:NSMakeRect(margin, top - size.height, width, size.height)];
		top -= size.height + margin;
		// Each group of buttons centered at the top of its page; every page opens at its first group.
		for (NSTabViewItem *item in [page tabViewItems]) {
			NSView *view = [item view];
			NSRect group = TSUnionOfSubviews(view);
			[view setFrame:[page contentRect]];
			// The views of a page (a group of buttons, and on some pages a note) keep their places among themselves.
			CGFloat dx = round((NSWidth([view bounds]) - NSWidth(group)) / 2) - NSMinX(group);
			CGFloat dy = NSHeight([view bounds]) - NSMaxY(group);
			for (NSView *subview in [view subviews])
				[subview setFrameOrigin:NSMakePoint(NSMinX([subview frame]) + dx, NSMinY([subview frame]) + dy)];
		}
		[page selectTabViewItemAtIndex:0];
		[chooser setSelectedSegment:0];
	}
	self.buttonPages = pages;
	self.pageChoosers = choosers;
}

@end
