/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard
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
 * $Id: MyPDFKitView.m 261 2007-08-09 20:10:11Z richard_koch $
 *
 * Parts of this code are taken from Apple's example PDFKitViewer.
 *
 */
 
 // WARNING --------------------------------------------
 // In Leopard, particularly when using the new Image Resolution ability, 
 // NSWindow's cacheImageInRect, restoreCachedImage, and discardCachedImage
 // do not work. Engineers at WWDC recommended better methods of rubber banding.
 // 
 // The code below is messy because the old cacheImage mechanism is present but
 // commented out. It has been replaced by equivalent methods which work on Leopard
 // and also on older operating systems.
 // Eventually I'll clean up these routines, but for the moment I thought it
 // best to leave the old code in place
 // -----------------------------------------------------

 // See comments below for further changes required by Mavericks. Koch.

// // QUESTIONABLE_BUG_FIX  (Search for this)

#import "ScrapPDFKitView.h"
#import "globals.h"
#import "TSDocument.h"
#import "TSEncodingSupport.h"
#import "TSColorSupport.h"
#import "TSPreviewAppearance.h"
#import "TSExperimentTheme.h"
#import "TSMagnifyingGlass.h"
#import "TSContentZoom.h"




// The Experiment preview offers four of the preview's mouse modes and remembers
// its own choice; the document preview's mode is not changed.
static NSString * const TSExperimentToolsToolbarID = @"TSExperimentTools";
static NSString * const TSExperimentZoomToolbarID = @"TSExperimentZoom";
static const NSInteger TSExperimentToolModes[] = {
    NEW_MOUSE_MODE_SCROLL, NEW_MOUSE_MODE_SELECT_TEXT, NEW_MOUSE_MODE_MAG_GLASS, NEW_MOUSE_MODE_SELECT_PDF };
static const NSInteger TSExperimentToolCount = 4;

@interface ScrapPDFKitView ()
@property (nonatomic) BOOL experimentViewReady;
@property (nonatomic) BOOL updatingExperimentAppearance;
@property (nonatomic, strong) NSToolbar *experimentToolbar;
@property (nonatomic) BOOL showsTopOfFirstPage;
@property (nonatomic, strong) OverView *experimentOverlay;
@property (nonatomic, strong) PDFPage *selectionPage;
@property (nonatomic) NSRect selectionPageRect;
@property (nonatomic, strong) PDFPage *lensPage;
@end

@implementation ScrapPDFKitView

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) _experimentViewReady = YES;
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) _experimentViewReady = YES;
    return self;
}

- (void)updateExperimentColors:(NSNotification *)notification
{
    if (!self.experimentViewReady || !self.window) return;
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSDictionary *theme = notification.userInfo ?: (dark ? darkColors : liteColors);
    self.backgroundColor = [[TSColorSupport sharedInstance] opaqueColorForKey:@"PreviewBackground"
        fromDictionary:theme isWindowDark:dark];
    self.window.alphaValue = TSThemeWindowAlpha(theme, TSThemePreviewAlphaKey);
}

- (void)updateExperimentAppearance:(NSNotification *)notification
{
    if (!self.experimentViewReady || self.updatingExperimentAppearance) return;
    self.updatingExperimentAppearance = YES;
    TSApplyPreviewInversion(self.documentView.enclosingScrollView,
        TSPreviewShouldInvert([SUD integerForKey:TSPreviewAppearanceModeKey], NSApp.effectiveAppearance));
    self.updatingExperimentAppearance = NO;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self name:SourceColorChangedNotification object:nil];
    [center removeObserver:self name:NSUserDefaultsDidChangeNotification object:SUD];
    [center removeObserver:self name:PDFViewScaleChangedNotification object:self];
    if (!self.window) return;
    [center addObserver:self selector:@selector(updateExperimentColors:)
        name:SourceColorChangedNotification object:nil];
    [center addObserver:self selector:@selector(experimentDefaultsChanged:)
        name:NSUserDefaultsDidChangeNotification object:SUD];
    [center addObserver:self selector:@selector(experimentScaleChanged:)
        name:PDFViewScaleChangedNotification object:self];
    if (!self.window.toolbar) {
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSExperimentPreviewToolbar"];
        toolbar.delegate = self;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        toolbar.allowsUserCustomization = NO;
        self.experimentToolbar = toolbar;
        self.window.toolbar = toolbar;
    }
    [self updateExperimentColors:nil];
    [self updateExperimentAppearance:nil];
}

- (void)experimentDefaultsChanged:(NSNotification *)notification
{
    [self updateExperimentAppearance:notification];
    [self syncExperimentToolSelection];
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    [self updateExperimentColors:nil];
    [self updateExperimentAppearance:nil];
}

- (void)setDocument:(PDFDocument *)document
{
    [self clearExperimentSelection];
    [self hideExperimentMagnifier];
    [super setDocument:document];
    [self updateExperimentAppearance:nil];
    // PDFKit may create its document scroll view on the following run-loop turn.
    __weak ScrapPDFKitView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf updateExperimentAppearance:nil]; });
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[TSExperimentToolsToolbarID, TSExperimentZoomToolbarID,
             NSToolbarFlexibleSpaceItemIdentifier, TSPreviewAppearanceToolbarID];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)inserted
{
    if ([identifier isEqualToString:TSExperimentToolsToolbarID]) return self.experimentToolsItem;
    if ([identifier isEqualToString:TSExperimentZoomToolbarID]) return self.experimentZoomItem;
    return [identifier isEqualToString:TSPreviewAppearanceToolbarID] ? TSPreviewAppearanceItem(self) : nil;
}

- (void)changePreviewAppearance:(NSMenuItem *)sender
{
    if (sender.tag < TSPreviewAppearanceSystem || sender.tag > TSPreviewAppearanceDark) return;
    [SUD setInteger:sender.tag forKey:TSPreviewAppearanceModeKey];
    [self updateExperimentAppearance:nil];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(changePreviewAppearance:))
        return TSValidatePreviewAppearanceChoice(item, SUD);
    if (item.action == @selector(copy:) && self.experimentMouseMode == NEW_MOUSE_MODE_SELECT_PDF)
        return self.hasExperimentSelection;
    return [super validateMenuItem:item];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    self.experimentToolbar.delegate = nil;
}




- (void) showWithPath: (NSString *)imagePath
{
	PDFDocument	*pdfDoc;
    
    NSDisableScreenUpdates();
	
    pdfDoc = [[PDFDocument alloc] initWithURL: [NSURL fileURLWithPath: imagePath]];
    [self setDocument: pdfDoc];

/*
	[self setup];
	totalPages = [[self document] pageCount];
	[totalPage setIntegerValue:totalPages];
	[totalPage1 setIntegerValue:totalPages];
	[totalPage display];
	[totalPage1 display];
	[[self document] setDelegate: self];
	[self setupOutline];
    NSEnableScreenUpdates();
	
	[self.myPDFWindow makeKeyAndOrderFront: self];
	if ([SUD boolForKey:PreviewDrawerOpenKey])
		[self toggleDrawer: self];
*/
}


- (void) reShowWithPath: (NSString *)imagePath
{
    PDFDocument *pdfDoc = [[PDFDocument alloc] initWithData:[NSData dataWithContentsOfFile:imagePath]];
    if (!pdfDoc || pdfDoc.pageCount == 0) return;
	BOOL            needsInitialization;
    NSRect          tempRect;
    NSRect          visibleRectA, fullRectA;
    
	// A note below explains dangers of NSDisableScreenUpdates
    // but these dangers don't apply to Intel on recent systems.
    // Experiments show that in single page mode, "disableFlushWindow"
    // adds a flash showing the initial page before switching to the
    // current page. NSDisableScreenUpdates fixes that.
    
    visibleRectA = [[self documentView] visibleRect];
	fullRectA = [[self documentView] bounds];

    
	// [[self window] disableFlushWindow];
    NSDisableScreenUpdates();
    
    
	if ([self document] == nil)
		needsInitialization = YES;
	else
		needsInitialization = NO;
    
    if (needsInitialization) {
        [self setAutoScales: YES];
       // [self setScaleFactor:3];
        }
    else {
        tempRect = [[self documentView] visibleRect];
        // tempRect.origin.y = tempRect.origin.y + tempRect.size.height;
        // tempRect.size.height = 1;
        // tempRect.size.width = 1;
        self.scrapVisibleRect = tempRect;
        self.scrapFullRect = [[self documentView] bounds];
        }

    
    // The data-backed snapshot remains valid after the temporary directory is removed.
    [self setDocument: pdfDoc];
    
    if (needsInitialization) {
        // A short Experiment's output is at the top of the first page.
        self.showsTopOfFirstPage = YES;
        [self showTopOfFirstPage];
        /*
        for (i = 1; i <= 10; i++)
            [self zoomIn:self];
        */
        /*
        myPage = [[self document] pageAtIndex:0];
        mySelection = [[self document] selectionFromPage:myPage atCharacterIndex: 2 toPage:myPage atCharacterIndex: 3];
        [self setCurrentSelection: mySelection];
        [self scrollSelectionToVisible: self];
         */
        }
    else
        /*
        {
        NSRect newFullRect = [[self documentView] bounds];
        NSInteger difference = newFullRect.size.height - self.scrapFullRect.size.height;
        original =  self.scrapVisibleRect.origin.y;
        [[self documentView] scrollRectToVisible: visibleRect];
            
        newVisibleRect = [[self documentView] visibleRect];
        new = newVisibleRect.origin.y;
        difference = original - new;
        newVisibleRect.origin.y = newVisibleRect.origin.y + difference;
        [[self documentView] scrollRectToVisible: newVisibleRect];
        }
        */
    {
        NSRect newFullRectA = [[self documentView] bounds];
        NSInteger differenceA = newFullRectA.size.height - fullRectA.size.height;
        
        visibleRectA.origin.y = visibleRectA.origin.y + differenceA - 5;
        [[self documentView] scrollRectToVisible: visibleRectA];
  
        
    }
    
    
	[[self document] setDelegate: self];
     NSEnableScreenUpdates();
	[self display]; //this is needed outside disableFlushWindow when the user does not bring the window forward
    
}



// PDFKit may place a document loaded into a hidden window elsewhere, and may
// lay the view out again when the window appears.
- (void)showTopOfFirstPage
{
    if (!self.document.pageCount) return;
    [self goToPage:[self.document pageAtIndex:0]];
    [self layoutDocumentView];
    [self layoutSubtreeIfNeeded];
    NSScrollView *scroll = self.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip) return;
    // The first page is in the top row, so ask the clip view for its top limit,
    // which keeps the native content insets.
    NSRect top = clip.bounds, documentRect = clip.documentRect;
    CGFloat beyond = NSHeight(top) + fabs(scroll.contentInsets.top) + fabs(scroll.contentInsets.bottom) + 1;
    top.origin.y = clip.isFlipped ? NSMinY(documentRect) - beyond : NSMaxY(documentRect) + beyond;
    top = [clip constrainBoundsRect:top];
    [clip scrollToPoint:top.origin];
    [scroll reflectScrolledClipView:clip];
}

- (void)didShowOutputWindow
{
    if (!self.showsTopOfFirstPage) return;
    [self showTopOfFirstPage];
    __weak ScrapPDFKitView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        ScrapPDFKitView *view = weakSelf;
        if (!view.showsTopOfFirstPage) return;
        view.showsTopOfFirstPage = NO;
        [view showTopOfFirstPage];
    });
}

#pragma mark - Experiment tools

static NSString *TSExperimentText(NSString *key, NSString *english)
{
    NSString *text = NSLocalizedStringFromTable(key, @"ToolbarItems", @"");
    return text.length && ![text isEqualToString:key] ? text : english;
}

static NSInteger TSExperimentToolIndex(NSInteger mode)
{
    for (NSInteger i = 0; i < TSExperimentToolCount; i++)
        if (TSExperimentToolModes[i] == mode) return i;
    return NSNotFound;
}

// The index of a group's control that sent an action, whether the group or one of its items sent it.
static NSInteger TSExperimentGroupIndex(id sender)
{
    if ([sender isKindOfClass:NSToolbarItemGroup.class]) return [(NSToolbarItemGroup *)sender selectedIndex];
    if ([sender isKindOfClass:NSToolbarItem.class])
        for (NSToolbarItem *item in [(NSToolbarItem *)sender toolbar].items)
            if ([item isKindOfClass:NSToolbarItemGroup.class] && [[(NSToolbarItemGroup *)item subitems] containsObject:sender])
                return [[(NSToolbarItemGroup *)item subitems] indexOfObject:sender];
    return NSNotFound;
}

// Image data of part of a page in a Copy Format type (TIFF, JPEG, PNG or PDF).
NSData *TSExperimentSelectionData(PDFPage *page, NSRect rect, NSInteger type, CGFloat pixelsPerPoint,
                                  NSPasteboardType *pasteboardType)
{
    if (!page || NSIsEmptyRect(rect)) return nil;
    PDFPage *part = [page copy];
    [part setBounds:rect forBox:kPDFDisplayBoxMediaBox];
    [part setBounds:rect forBox:kPDFDisplayBoxCropBox];
    if (type == IMAGE_TYPE_PDF) {
        PDFDocument *document = [PDFDocument new];
        [document insertPage:part atIndex:0];
        if (pasteboardType) *pasteboardType = NSPasteboardTypePDF;
        return document.dataRepresentation;
    }
    BOOL turned = part.rotation % 180 != 0;
    NSSize size = turned ? NSMakeSize(NSHeight(rect), NSWidth(rect)) : rect.size;
    NSInteger width = MAX(1, lround(size.width * pixelsPerPoint)), height = MAX(1, lround(size.height * pixelsPerPoint));
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    if (!bitmap) return nil;
    bitmap.size = size;
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    [NSColor.whiteColor setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [part drawWithBox:kPDFDisplayBoxCropBox toContext:context.CGContext];
    [NSGraphicsContext restoreGraphicsState];
    NSBitmapImageFileType fileType = NSBitmapImageFileTypePNG;
    NSDictionary *properties = @{};
    NSPasteboardType kind = NSPasteboardTypePNG;
    switch (type) {
        case IMAGE_TYPE_TIFF_NC: case IMAGE_TYPE_TIFF_LZW: case IMAGE_TYPE_TIFF_PB:
            fileType = NSBitmapImageFileTypeTIFF;
            kind = NSPasteboardTypeTIFF;
            properties = @{NSImageCompressionMethod: @(type == IMAGE_TYPE_TIFF_NC ? NSTIFFCompressionNone :
                type == IMAGE_TYPE_TIFF_LZW ? NSTIFFCompressionLZW : NSTIFFCompressionPackBits)};
            break;
        case IMAGE_TYPE_JPEG_HIGH: case IMAGE_TYPE_JPEG_MEDIUM: case IMAGE_TYPE_JPEG_LOW:
            fileType = NSBitmapImageFileTypeJPEG;
            kind = @"public.jpeg";
            properties = @{NSImageCompressionFactor: @(type == IMAGE_TYPE_JPEG_HIGH ? JPEG_COMPRESSION_HIGH :
                type == IMAGE_TYPE_JPEG_MEDIUM ? JPEG_COMPRESSION_MEDIUM : JPEG_COMPRESSION_LOW)};
            break;
        default: // PNG, and formats the Copy Format menu no longer offers
            break;
    }
    if (pasteboardType) *pasteboardType = kind;
    return [bitmap representationUsingType:fileType properties:properties];
}

- (NSInteger)experimentMouseMode
{
    NSInteger mode = [SUD integerForKey:ExperimentMouseModeKey];
    return TSExperimentToolIndex(mode) == NSNotFound ? NEW_MOUSE_MODE_SELECT_TEXT : mode;
}

- (NSToolbarItem *)experimentToolsItem
{
    NSArray *symbols = @[@"hand.point.up.left", @"a", @"text.magnifyingglass", @"rectangle.dashed"];
    NSArray *labels = @[TSExperimentText(@"ExperimentToolScroll", @"Scroll"),
                        TSExperimentText(@"ExperimentToolSelectText", @"Select Text"),
                        TSExperimentText(@"ExperimentToolMagnify", @"Magnify"),
                        TSExperimentText(@"ExperimentToolSelectPDF", @"Select PDF")];
    NSMutableArray *images = [NSMutableArray array];
    for (NSUInteger i = 0; i < symbols.count; i++)
        [images addObject:[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:labels[i]]];
    NSToolbarItemGroup *group = [NSToolbarItemGroup groupWithItemIdentifier:TSExperimentToolsToolbarID images:images
        selectionMode:NSToolbarItemGroupSelectionModeSelectOne labels:labels target:self action:@selector(changeExperimentTool:)];
    // Kept as separate buttons: AppKit would size them by their labels and fold them into a menu.
    group.controlRepresentation = NSToolbarItemGroupControlRepresentationExpanded;
    group.label = group.paletteLabel = TSExperimentText(@"tiLabelMouseModeKIT", @"Mouse Mode");
    for (NSUInteger i = 0; i < group.subitems.count; i++) group.subitems[i].toolTip = labels[i];
    group.selectedIndex = TSExperimentToolIndex(self.experimentMouseMode);
    return group;
}

- (NSToolbarItem *)experimentZoomItem
{
    NSArray *symbols = [@[@"minus.magnifyingglass", @"plus.magnifyingglass"] arrayByAddingObjectsFromArray:TSContentZoomSymbols()];
    NSArray *labels = [@[TSExperimentText(@"ExperimentZoomOut", @"Zoom Out"),
                         TSExperimentText(@"ExperimentZoomIn", @"Zoom In")] arrayByAddingObjectsFromArray:TSContentZoomLabels()];
    NSMutableArray *images = [NSMutableArray array];
    for (NSUInteger i = 0; i < symbols.count; i++)
        [images addObject:[NSImage imageWithSystemSymbolName:symbols[i] accessibilityDescription:labels[i]]];
    NSToolbarItemGroup *group = [NSToolbarItemGroup groupWithItemIdentifier:TSExperimentZoomToolbarID images:images
        selectionMode:NSToolbarItemGroupSelectionModeMomentary labels:labels target:self action:@selector(experimentZoom:)];
    // Kept as separate buttons: AppKit would size them by their labels and fold them into a menu.
    group.controlRepresentation = NSToolbarItemGroupControlRepresentationExpanded;
    group.label = group.paletteLabel = TSExperimentText(@"tiLabelMagnificationKIT", @"Magnification");
    for (NSUInteger i = 0; i < group.subitems.count; i++) group.subitems[i].toolTip = labels[i];
    return group;
}

// Another Experiment window may have changed the shared choice.
- (void)syncExperimentToolSelection
{
    NSInteger index = TSExperimentToolIndex(self.experimentMouseMode);
    for (NSToolbarItem *item in self.window.toolbar.items)
        if ([item.itemIdentifier isEqualToString:TSExperimentToolsToolbarID] &&
            [(NSToolbarItemGroup *)item selectedIndex] != index) {
            [(NSToolbarItemGroup *)item setSelectedIndex:index];
            [self clearExperimentSelection];
            [self.window invalidateCursorRectsForView:self];
        }
}

- (void)changeExperimentTool:(id)sender
{
    NSInteger index = TSExperimentGroupIndex(sender);
    if (index == NSNotFound || index < 0 || index >= TSExperimentToolCount) return;
    [self clearExperimentSelection];
    [SUD setInteger:TSExperimentToolModes[index] forKey:ExperimentMouseModeKey];
    [self.window invalidateCursorRectsForView:self];
}

- (void)experimentZoom:(id)sender
{
    switch (TSExperimentGroupIndex(sender)) {
        case 0: [self zoomOut:sender]; break;
        case 1: [self zoomIn:sender]; break;
        case 2: [self zoomToContentWidthOnly:NO]; break;
        case 3: [self zoomToContentWidthOnly:YES]; break;
        default: break;
    }
}

// Zoom to Content, or Zoom to Content Width (TSContentZoom.h).
- (void)zoomToContentWidthOnly:(BOOL)widthOnly
{
    CGFloat least = self.minScaleFactor, most = MIN(self.maxScaleFactor, 8.0);
    TSContentZoom(self, widthOnly, ^CGFloat(CGFloat scale) {
        [self clearExperimentSelection];
        self.autoScales = NO;
        self.scaleFactor = MAX(least, MIN(scale, most));
        return self.scaleFactor;
    });
}

- (OverView *)experimentOverlayView
{
    if (!self.experimentOverlay || self.experimentOverlay.superview != self.documentView) {
        [self.experimentOverlay removeFromSuperview];
        self.experimentOverlay = [[OverView alloc] initWithFrame:self.documentView.frame];
        [self.documentView addSubview:self.experimentOverlay];
    }
    return self.experimentOverlay;
}

- (void)removeExperimentOverlay
{
    [self.experimentOverlay removeFromSuperview];
    self.experimentOverlay = nil;
}

- (BOOL)hasExperimentSelection
{
    return self.selectionPage != nil && NSWidth(self.selectionPageRect) >= 1 && NSHeight(self.selectionPageRect) >= 1;
}

- (void)clearExperimentSelection
{
    self.selectionPage = nil;
    self.selectionPageRect = NSZeroRect;
    [self removeExperimentOverlay];
}

// Points are in document view coordinates, as the rubber band is drawn there.
- (void)setExperimentSelectionFrom:(NSPoint)start to:(NSPoint)end square:(BOOL)square
{
    NSRect band = NSMakeRect(MIN(start.x, end.x), MIN(start.y, end.y), fabs(end.x - start.x), fabs(end.y - start.y));
    if (square) {
        CGFloat side = MAX(NSWidth(band), NSHeight(band));
        band.origin.x = end.x < start.x ? start.x - side : start.x;
        band.origin.y = end.y < start.y ? start.y - side : start.y;
        band.size = NSMakeSize(side, side);
    }
    OverView *overlay = [self experimentOverlayView];
    [overlay setDrawMagnifiedImage:NO];
    [overlay setDrawMagnifiedRect:NO];
    [overlay setDrawRubberBand:YES];
    [overlay setSelectionRect:band];
    [overlay setNeedsDisplay:YES];
    NSRect inView = [self convertRect:band fromView:self.documentView];
    PDFPage *page = [self pageForPoint:NSMakePoint(NSMidX(inView), NSMidY(inView)) nearest:YES];
    self.selectionPage = page;
    self.selectionPageRect = page ? NSIntersectionRect([self convertRect:inView toPage:page], [page boundsForBox:self.displayBox]) : NSZeroRect;
}

- (void)showExperimentMagnifierAt:(NSPoint)point level:(NSInteger)level modifiers:(NSEventModifierFlags)flags
{
    PDFPage *page = [self pageForPoint:point nearest:YES];
    if (!page) return;
    // Same glass as the Preview window (TSMagnifyingGlass.h).
    PDFDisplayBox box = self.displayBox;
    self.lensPage = page;
    NSRect onScreen, drawn;
    TSMagnifyingGlassLayout(self, page, box, point, TSMagnifyingGlassSize(level), TSMagnifyingGlassScale(flags), &onScreen, &drawn);
    OverView *overlay = [self experimentOverlayView];
    [overlay setDrawRubberBand:NO];
    [overlay setDrawMagnifiedRect:NO];
    [overlay setDrawMagnifiedImage:YES];
    [overlay setSelectionRect:[self.documentView convertRect:onScreen fromView:self]];
    [overlay setMagnifiedRect:drawn];
    overlay.magnifiedPage = page;
    overlay.magnifiedBox = box;
    [overlay setNeedsDisplay:YES];
}

- (void)hideExperimentMagnifier
{
    [self removeExperimentOverlay];
    self.lensPage = nil;
}

// Drags the view under the pointer; window deltas are in points.
- (void)scrollExperimentFromOrigin:(NSPoint)origin byDelta:(NSSize)delta
{
    NSScrollView *scroll = self.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip || NSWidth(clip.frame) <= 0) return;
    CGFloat unit = NSWidth(clip.bounds) / NSWidth(clip.frame);
    NSRect target = clip.bounds;
    target.origin.x = origin.x - delta.width * unit;
    target.origin.y = clip.isFlipped ? origin.y + delta.height * unit : origin.y - delta.height * unit;
    target = [clip constrainBoundsRect:target];
    [clip scrollToPoint:target.origin];
    [scroll reflectScrolledClipView:clip];
}

- (void)scrollExperimentByDragging:(NSEvent *)event
{
    NSClipView *clip = self.documentView.enclosingScrollView.contentView;
    if (!clip) return;
    NSPoint start = event.locationInWindow, origin = clip.bounds.origin;
    [NSCursor.closedHandCursor push];
    do {
        event = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged];
        if (event.type == NSEventTypeLeftMouseDragged)
            [self scrollExperimentFromOrigin:origin byDelta:NSMakeSize(event.locationInWindow.x - start.x,
                                                                       event.locationInWindow.y - start.y)];
    } while (event && event.type != NSEventTypeLeftMouseUp);
    [NSCursor pop];
}

- (void)magnifyExperiment:(NSEvent *)event
{
    [self clearExperimentSelection];
    NSInteger level = event.clickCount;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    BOOL hidden = NO;
    while (event && event.type != NSEventTypeLeftMouseUp) {
        if (event.type != NSEventTypeFlagsChanged)
            point = [self convertPoint:event.locationInWindow fromView:nil];
        if ([self mouse:point inRect:self.visibleRect]) {
            if (!hidden) { [NSCursor hide]; hidden = YES; }
            [self showExperimentMagnifierAt:point level:level modifiers:event.modifierFlags];
        } else {
            if (hidden) { [NSCursor unhide]; hidden = NO; }
            [self removeExperimentOverlay];
        }
        event = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged | NSEventMaskFlagsChanged];
    }
    [self hideExperimentMagnifier];
    if (hidden) [NSCursor unhide];
}

- (void)selectExperimentRect:(NSEvent *)event
{
    [self clearExperimentSelection];
    NSPoint start = [self.documentView convertPoint:event.locationInWindow fromView:nil], end = start;
    while (event && event.type != NSEventTypeLeftMouseUp) {
        if (event.type != NSEventTypeFlagsChanged) {
            end = [self.documentView convertPoint:event.locationInWindow fromView:nil];
            if (event.type == NSEventTypeLeftMouseDragged) [self.documentView autoscroll:event];
        }
        [self setExperimentSelectionFrom:start to:end square:(event.modifierFlags & NSEventModifierFlagShift) != 0];
        event = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged | NSEventMaskFlagsChanged];
    }
    if (!self.hasExperimentSelection) [self clearExperimentSelection];
}

- (void)mouseDown:(NSEvent *)event
{
    switch (self.experimentMouseMode) {
        case NEW_MOUSE_MODE_SCROLL:
            [self clearExperimentSelection];
            [self scrollExperimentByDragging:event];
            break;
        case NEW_MOUSE_MODE_MAG_GLASS:
            [self magnifyExperiment:event];
            break;
        case NEW_MOUSE_MODE_SELECT_PDF:
            [self selectExperimentRect:event];
            break;
        default:
            [self clearExperimentSelection];
            [super mouseDown:event];
    }
}

- (NSCursor *)experimentToolCursor
{
    switch (self.experimentMouseMode) {
        case NEW_MOUSE_MODE_SCROLL: return NSCursor.openHandCursor;
        case NEW_MOUSE_MODE_SELECT_PDF: return NSCursor.crosshairCursor;
        case NEW_MOUSE_MODE_MAG_GLASS: return NSCursor.arrowCursor;
        default: return nil;
    }
}

- (void)resetCursorRects
{
    NSCursor *cursor = self.experimentToolCursor;
    if (cursor) [self addCursorRect:self.visibleRect cursor:cursor];
    else [super resetCursorRects];
}

// PDFKit sets its own cursor over text and links while the pointer moves.
- (void)mouseMoved:(NSEvent *)event
{
    NSCursor *cursor = self.experimentToolCursor;
    if (cursor) [cursor set];
    else [super mouseMoved:event];
}

- (void)copy:(id)sender
{
    if (self.experimentMouseMode != NEW_MOUSE_MODE_SELECT_PDF || !self.hasExperimentSelection) {
        [super copy:sender];
        return;
    }
    NSPasteboardType kind = nil;
    CGFloat backing = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 2;
    NSData *data = TSExperimentSelectionData(self.selectionPage, self.selectionPageRect,
        [SUD integerForKey:PdfCopyTypeKey], MAX(1.0, self.scaleFactor * backing), &kind);
    if (!data) { NSBeep(); return; }
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setData:data forType:kind];
}

- (void)experimentScaleChanged:(NSNotification *)notification
{
    // The rubber band is drawn at the old scale; select again after zooming.
    [self clearExperimentSelection];
}

@end
