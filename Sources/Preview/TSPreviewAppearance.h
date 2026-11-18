// added by Terada (from this line)
#pragma once
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

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
static inline BOOL TSPreviewSubviewIsToolbarPocket(NSView *view) {
    return [NSStringFromClass(view.class) containsString:@"Pocket"];
}

// Share the same PDF page treatment between the document and Experiment previews.
// The appearance chosen for the preview applies to the pages and the area around
// them. It does not apply to the window frame, which keeps the system's appearance.
static inline void TSApplyPreviewInversion(NSScrollView *scrollView, BOOL invert) {
    if (!scrollView) return;
    scrollView.appearance = nil;
    // Filters on the scroll view would also invert the pocket under the toolbar.
    scrollView.contentFilters = @[];
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    for (NSView *subview in scrollView.subviews) {
        if (TSPreviewSubviewIsToolbarPocket(subview)) {
            subview.appearance = nil;
            subview.contentFilters = @[];
            continue;
        }
        // PDFKit must draw light pages before the luminosity filter is applied.
        // The view behind the pages is light too, so the area around them matches.
        subview.appearance = light;
        subview.contentFilters = invert ? TSPreviewInversionFilters() : @[];
    }
}
