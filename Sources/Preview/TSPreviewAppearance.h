// added by Terada (from this line)
#pragma once
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <objc/runtime.h>

static NSString * const TSPreviewAppearanceModeKey = @"TSPreviewAppearanceMode";
static NSString * const TSPreviewAppearanceToolbarID = @"TSPreviewAppearance";

typedef NS_ENUM(NSInteger, TSPreviewAppearanceMode) {
    TSPreviewAppearanceSystem = 0,
    TSPreviewAppearanceLight = 1,
    TSPreviewAppearanceDark = 2
};

static inline BOOL TSPreviewShouldInvert(NSInteger mode, NSAppearance *systemAppearance) {
    if (mode == TSPreviewAppearanceLight) return NO;
    if (mode == TSPreviewAppearanceDark) return YES;
    NSString *match = [systemAppearance bestMatchFromAppearancesWithNames:
                      @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

// The Preview color of a theme is the paper of pages shown light. Pages shown dark
// keep PDFKit's own paper, which the luminosity filter turns deep black.
static inline NSColor *TSPreviewPaperColor(NSInteger mode, NSAppearance *systemAppearance, NSColor *themeColor) {
    return TSPreviewShouldInvert(mode, systemAppearance) ? nil : themeColor;
}

// Fills the box of page that -[PDFPage drawWithBox:toContext:] draws; nothing for nil.
static inline void TSFillPreviewPaper(CGContextRef context, PDFPage *page, PDFDisplayBox box, NSColor *color) {
    if (!context || !page || !color) return;
    CGContextSaveGState(context);
    CGContextConcatCTM(context, [page transformForBox:box]);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, NSRectToCGRect([page boundsForBox:box]));
    CGContextRestoreGState(context);
}

// PDFKit keeps drawn pages; have it draw them again after the paper has changed.
// Marking the PDF view redraws the pages shown, and PDFKit draws the others again
// when they are scrolled back; -annotationsChangedOnPage: draws nothing again.
static inline void TSRedrawPreviewPages(PDFView *view) {
    [view setNeedsDisplay:YES];
}

static inline NSMenuToolbarItem *TSPreviewAppearanceItem(id target) {
    NSMenuToolbarItem *item = [[NSMenuToolbarItem alloc] initWithItemIdentifier:TSPreviewAppearanceToolbarID];
    NSString *label = NSLocalizedStringFromTable(@"tiLabelTSPreviewAppearance", @"ToolbarItems", @"Appearance");
    if ([label isEqualToString:@"tiLabelTSPreviewAppearance"]) label = @"Appearance";
    item.label = label;
    item.paletteLabel = label;
    item.toolTip = label;
    item.image = [NSImage imageWithSystemSymbolName:@"circle.righthalf.filled" accessibilityDescription:label];
    item.showsIndicator = YES;
    item.visibilityPriority = NSToolbarItemVisibilityPriorityHigh;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:label];
    NSArray *keys = @[@"PreviewAppearanceSystem", @"PreviewAppearanceLight", @"PreviewAppearanceDark"];
    NSArray *fallback = @[@"System", @"Light", @"Dark"];
    for (NSInteger i = 0; i < 3; i++) {
        NSString *title = NSLocalizedStringFromTable(keys[i], @"ToolbarItems", @"");
        if ([title isEqualToString:keys[i]]) title = fallback[i];
        NSMenuItem *choice = [[NSMenuItem alloc] initWithTitle:title
            action:NSSelectorFromString(@"changePreviewAppearance:") keyEquivalent:@""];
        choice.target = target;
        choice.tag = i;
        [menu addItem:choice];
    }
    item.menu = menu;
    return item;
}

static inline BOOL TSValidatePreviewAppearanceChoice(NSMenuItem *item, NSUserDefaults *defaults) {
    item.state = item.tag == [defaults integerForKey:TSPreviewAppearanceModeKey]
        ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}
// added by Terada (until this line)

// The luminosity filter turns light pages dark. PDFKit has to draw those pages
// light first, so the same three filters are shared by the document preview and
// the Experiment preview.
static inline NSArray *TSPreviewInversionFilters(void) {
    NSMutableArray *filters = [NSMutableArray array];
    CIFilter *filter;

    // Step 1: Linearise (gamma pre-correction)
    filter = [CIFilter filterWithName:@"CIGammaAdjust"
        keysAndValues:@"inputPower",
        [NSNumber numberWithDouble:0.625], nil];
    if (filter) [filters addObject:filter];

    // Step 2: Luminosity inversion via colour matrix
    // Tuning factor: white -> ~#1E1E1E
    CGFloat f = [[NSWorkspace sharedWorkspace]
        accessibilityDisplayShouldIncreaseContrast]
        ? 1.9337 : 1.8972;

    filter = [CIFilter filterWithName:@"CIColorMatrix"
        keysAndValues:
        @"inputRVector",
            [CIVector vectorWithX:1.0-0.2126*f Y:-0.7152*f Z:-0.0722*f W:0.0],
        @"inputGVector",
            [CIVector vectorWithX:-0.2126*f Y:1.0-0.7152*f Z:-0.0722*f W:0.0],
        @"inputBVector",
            [CIVector vectorWithX:-0.2126*f Y:-0.7152*f Z:1.0-0.0722*f W:0.0],
        @"inputAVector",
            [CIVector vectorWithX:0.0 Y:0.0 Z:0.0 W:1.0],
        @"inputBiasVector",
            [CIVector vectorWithX:1.0 Y:1.0 Z:1.0 W:0.0],
        nil];
    if (filter) [filters addObject:filter];

    // Step 3: Re-apply gamma
    filter = [CIFilter filterWithName:@"CIGammaAdjust"
        keysAndValues:@"inputPower",
        [NSNumber numberWithDouble:1.6], nil];
    if (filter) [filters addObject:filter];
    return filters;
}

// NSScrollPocket and the backdrop behind it fill the band under the title bar.
// On macOS 26 and later, where the preview runs under the toolbar, AppKit copies
// the scroll view's appearance onto that title bar. The pocket has to keep the
// window's appearance, or a light preview turns the window frame light too.
// The class name is how the pocket is told from the gutter beside it. A pocket
// is never given the preview's appearance.
static inline BOOL TSPreviewSubviewIsToolbarPocket(NSView *view) {
    return [NSStringFromClass(view.class) containsString:@"Pocket"];
}

// The key is private to each file that includes this header. The preview that applies
// the appearance and the preview that meets a new page view are the same file.
static void *TSPreviewInversionStateKey = &TSPreviewInversionStateKey;

// Share the same PDF page treatment between the document and Experiment previews.
// Scroll bars are part of the window frame. They take no explicit appearance and no
// filters, so they follow the system whether the preview is light or dark.
// On macOS 27 an overlay scroller's effective appearance copies the clip view and the
// document view, not the scroller's own appearance and not PDFPageView. Those two
// views therefore stay unset. Each PDFPageView is drawn light, and the luminosity
// filter is applied there. The gutter around the pages is drawn light the same way.
// The pocket stays unset so the title bar is not pulled off the system appearance.
static inline void TSApplyPreviewInversion(NSScrollView *scrollView, BOOL invert) {
    if (!scrollView) return;
    scrollView.appearance = nil;
    // Filters on the scroll view would also invert the pocket under the toolbar.
    scrollView.contentFilters = @[];
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSArray *filters = invert ? TSPreviewInversionFilters() : @[];
    for (NSView *subview in scrollView.subviews) {
        if (TSPreviewSubviewIsToolbarPocket(subview) ||
            [subview isKindOfClass:[NSScroller class]] ||
            subview == scrollView.contentView) {
            // Scroll bars, the clip, and the pocket. Aqua on the clip is copied
            // onto an overlay scroller, so the bar would leave the system appearance.
            subview.appearance = nil;
            subview.contentFilters = @[];
            continue;
        }
        subview.appearance = light;
        subview.contentFilters = filters;
    }
    NSView *documentView = scrollView.documentView;
    // The document view's appearance is copied onto an overlay scroller too.
    documentView.appearance = nil;
    documentView.contentFilters = @[];
    for (NSView *child in documentView.subviews) {
        // PDFPageView draws the page. Its appearance is not copied onto the scroller.
        if (![NSStringFromClass(child.class) containsString:@"Page"]) {
            child.appearance = nil;
            child.contentFilters = @[];
            continue;
        }
        child.appearance = light;
        child.contentFilters = filters;
    }
    // A page view PDFKit adds later was not in this list.
    objc_setAssociatedObject(scrollView, &TSPreviewInversionStateKey, @(invert),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Gives a page view that appeared after the choice was made the same treatment.
static inline void TSReapplyPreviewInversion(NSScrollView *scrollView) {
    NSNumber *invert = objc_getAssociatedObject(scrollView, &TSPreviewInversionStateKey);
    if (!invert) return;
    TSApplyPreviewInversion(scrollView, invert.boolValue);
}
