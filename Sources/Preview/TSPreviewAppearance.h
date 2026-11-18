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

// The choice made for a scroll view. Selectors are the same in every file that includes
// this header, so the hook below finds the state another file stored.
#define TSPreviewInversionStateKey @selector(tsPreviewInversionState)

// The pages, and the views TeXShop places over them (link popups, the magnifying glass,
// selections), are drawn light. Their appearance is set view by view, because Aqua on
// the document view is copied onto an overlay scroller.
static inline void TSLightenPreviewPageView(NSView *child) {
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    if (child.appearance != light) child.appearance = light;
    if (child.contentFilters.count) child.contentFilters = @[];
}
static inline void TSLightenPreviewPages(NSView *documentView) {
    for (NSView *child in documentView.subviews) TSLightenPreviewPageView(child);
}

static void TSInstallPreviewPageHook(NSView *documentView);

// Share the same PDF page treatment between the document and Experiment previews.
// Scroll bars are part of the window frame. They take no explicit appearance and no
// filters, so they follow the system whether the preview is light or dark.
// On macOS 27 an overlay scroller's effective appearance copies the clip view and the
// document view, so those two take no appearance. The luminosity filter is set on the
// document view: filters belong to its layer, so they reach every page view PDFKit adds
// later, at once, and never the scrollers beside it. The gutter around the pages is drawn
// light and inverted the same way. The pocket stays unset so the title bar is not pulled
// off the system appearance.
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
    documentView.appearance = nil;
    documentView.contentFilters = filters;
    TSInstallPreviewPageHook(documentView);
    TSLightenPreviewPages(documentView);
    objc_setAssociatedObject(scrollView, TSPreviewInversionStateKey, @(invert),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Applies the choice again, as after -setDocument:, which puts a new document view in.
static inline void TSReapplyPreviewInversion(NSScrollView *scrollView) {
    NSNumber *invert = objc_getAssociatedObject(scrollView, TSPreviewInversionStateKey);
    if (!invert) return;
    TSApplyPreviewInversion(scrollView, invert.boolValue);
}

// A page view PDFKit adds while scrolling, or after a new document or display format, is
// made light the moment PDFKit adds it to the document view: -didAddSubview: of the
// document view's class calls the original method and then lightens the new view, when
// the view belongs to a preview (its scroll view carries the choice). Each class that
// gets the hook gets its own implementation, which holds that class's original, so a
// subclass and its superclass can both be hooked without either reaching the other's
// hook as its original. A class that only inherits the method from a hooked ancestor is
// left to that ancestor. When PDFKit's class is not the usual one, nothing changes but
// the hook: the filters on the document view still invert the pages.
static void TSInstallPreviewPageHook(NSView *documentView) {
    Class cls = [documentView class];
    if (!cls || cls == NSView.class) return;
    SEL sel = @selector(didAddSubview:);
    @synchronized (NSView.class) {
        if (objc_getAssociatedObject(cls, @selector(tsPreviewPageHook))) return;
        Method own = NULL;
        unsigned count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned i = 0; i < count; i++) if (method_getName(methods[i]) == sel) own = methods[i];
        free(methods);
        if (!own) {
            for (Class up = class_getSuperclass(cls); up && up != NSView.class; up = class_getSuperclass(up))
                if (objc_getAssociatedObject(up, @selector(tsPreviewPageHook))) return;
        }
        IMP original = own ? method_getImplementation(own)
                           : class_getMethodImplementation(class_getSuperclass(cls), sel);
        IMP hook = imp_implementationWithBlock(^(__unsafe_unretained NSView *view, NSView *subview) {
            ((void (*)(__unsafe_unretained id, SEL, NSView *))original)(view, sel, subview);
            if (objc_getAssociatedObject(view.enclosingScrollView, TSPreviewInversionStateKey))
                TSLightenPreviewPageView(subview);
        });
        if (own) method_setImplementation(own, hook);
        else class_addMethod(cls, sel, hook, "v@:@");
        objc_setAssociatedObject(cls, @selector(tsPreviewPageHook), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// -setDocument: puts a new document view in. The choice is applied to it at once, while it
// has no page views yet, so they arrive under the preview's filters and are made light as
// they come. The document preview and the Experiment preview set their documents through this.
static inline void TSPreviewSetDocument(PDFView *view, void (NS_NOESCAPE ^set)(void)) {
    set();
    TSInstallPreviewPageHook(view.documentView);
    TSReapplyPreviewInversion(view.documentView.enclosingScrollView);
}
