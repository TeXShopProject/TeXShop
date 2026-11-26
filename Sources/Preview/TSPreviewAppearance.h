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

// The Preview color of a theme is the paper of pages shown light. Pages shown dark are
// drawn on white paper, which the luminosity filter turns deep black.
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
#define TSPreviewInversionStateKey sel_getUid("tsPreviewInversionState")
// Set on the preview window while it is in full screen. The window's own appearance
// is dark then, like Preview.app, even when the system is light.
#define TSPreviewFullScreenDarkKey sel_getUid("tsPreviewFullScreenDark")

// Whether the pages of a PDF view are drawn inverted. PDFKit draws pages on its own
// threads, so the choice is kept on the PDF view itself, where those threads read it.
#define TSPreviewPagesInvertedKey sel_getUid("tsPreviewPagesInverted")
static inline BOOL TSPreviewPagesInverted(NSView *pdfView) {
    return [objc_getAssociatedObject(pdfView, TSPreviewPagesInvertedKey) boolValue];
}

// A dark preview inverts the pages as PDFKit draws them, in the bitmaps that hold the page
// at the resolution of the screen. A filter on a view would not do: PDFKit magnifies
// through the clip view's own layer transform, so a filter on the clip view, the document
// view or a page view is rendered at the page's unmagnified size, and the pages blurred
// when zoomed in (6.00 beta 4). The same three filters run in the same color space as a
// filter on a view, so the colors do not change. The page is drawn on white first, as on
// PDFKit's paper. The returned image is owned by the caller; NULL if it cannot be made.
static inline CGImageRef TSPreviewCreateInvertedImage(CGImageRef image) CF_RETURNS_RETAINED {
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}]; });
    if (!image) return NULL;
    CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CIImage *result = [CIImage imageWithCGImage:image options:@{kCIImageColorSpace: (__bridge id)sRGB}];
    CGRect extent = result.extent;
    for (CIFilter *filter in TSPreviewInversionFilters()) {
        [filter setValue:result forKey:kCIInputImageKey];
        result = filter.outputImage;
    }
    CGImageRef inverted = result ? [context createCGImage:result fromRect:extent format:kCIFormatRGBA8 colorSpace:sRGB] : NULL;
    CGColorSpaceRelease(sRGB);
    return inverted;
}

// Inside a page view PDFKit keeps, besides the tiles of the page, layers that are not
// drawn through -drawPage:toContext:. The white paper behind the tiles and the small
// picture of the page shown until the tiles are drawn take the filters of a dark preview, so a page does not flash white while it is drawn
// (they hold no fine detail, so their size does not matter). A selection is drawn by
// layers multiplied over the page, which would darken a dark page further and leave the
// selection hard to see; for a dark preview the layer of each selection effect (a few
// levels down: the selection and the highlights of found text) has its colors inverted and
// is screened over the page instead, which shows it as it was shown on a light page that was
// then inverted. The compositing PDFKit set is kept and given back to a light preview.
#define TSPreviewSelectionCompositingKey sel_getUid("tsPreviewSelectionCompositing")
#define TSPreviewEffectFiltersKey sel_getUid("tsPreviewEffectFilters")
static void TSPreparePreviewSelectionLayers(CALayer *layer, NSArray *filters, int depth) {
    BOOL invert = filters.count > 0;
    for (CALayer *sublayer in layer.sublayers) {
        NSString *name = NSStringFromClass(sublayer.class);
        if ([name containsString:@"Tile"]) continue;
        if (![name containsString:@"SelectionEffect"]) {
            if (depth < 4) TSPreparePreviewSelectionLayers(sublayer, filters, depth + 1);
            continue;
        }
        // The effect layer with filters is drawn as a group of its own, so whatever PDFKit sets
        // on the layers inside (it multiplies them, and sets that again when the page is zoomed)
        // gives the selection's own colors there. Those are inverted and screened over the page.
        id kept = objc_getAssociatedObject(sublayer, TSPreviewSelectionCompositingKey);
        BOOL added = objc_getAssociatedObject(sublayer, TSPreviewEffectFiltersKey) != nil;
        if (invert) {
            if (!kept) objc_setAssociatedObject(sublayer, TSPreviewSelectionCompositingKey,
                sublayer.compositingFilter ?: NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!sublayer.filters.count) {
                sublayer.filters = filters;
                objc_setAssociatedObject(sublayer, TSPreviewEffectFiltersKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (![sublayer.compositingFilter isEqual:@"screenBlendMode"]) sublayer.compositingFilter = @"screenBlendMode";
        } else {
            // Only the filters this function put on are taken off; a layer's own filters stay.
            if (added) {
                sublayer.filters = nil;
                objc_setAssociatedObject(sublayer, TSPreviewEffectFiltersKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (kept) {
                sublayer.compositingFilter = kept == NSNull.null ? nil : kept;
                objc_setAssociatedObject(sublayer, TSPreviewSelectionCompositingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}
static inline void TSPreparePreviewPageLayers(NSView *pageView, NSArray *filters) {
    CALayer *pageLayer = pageView.layer;
    if (!pageLayer) return;
    BOOL invert = filters.count > 0;
    if (invert && !pageView.layerUsesCoreImageFilters) pageView.layerUsesCoreImageFilters = YES;
    for (CALayer *layer in pageLayer.sublayers) {
        // The paper and the picture have a color or contents and no sublayers. The layer
        // that holds the tiles has neither, also while it is still empty, and never takes
        // the filters: its tiles are inverted already.
        BOOL tiles = NO;
        for (CALayer *sublayer in layer.sublayers)
            if ([NSStringFromClass(sublayer.class) containsString:@"Tile"]) tiles = YES;
        BOOL paper = !tiles && layer.sublayers.count == 0 && (layer.backgroundColor || layer.contents);
        // Only filters this function put on are taken off again; a layer it never touched keeps its own.
        BOOL marked = objc_getAssociatedObject(layer, TSPreviewSelectionCompositingKey) != nil;
        if (invert && paper && !layer.filters.count) {
            layer.filters = filters;
            objc_setAssociatedObject(layer, TSPreviewSelectionCompositingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (marked && !(invert && paper)) {
            layer.filters = nil;
            objc_setAssociatedObject(layer, TSPreviewSelectionCompositingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    TSPreparePreviewSelectionLayers(pageLayer, filters, 0);
}

// The pages, and the views TeXShop places over them (link popups, the magnifying glass,
// selections), are drawn light. Their appearance is set view by view, because Aqua on
// the document view is copied onto an overlay scroller. A page view carries no filter:
// its page is inverted as it is drawn, and only the layers above are prepared. A view
// over the pages carries the filters of a dark preview.
static inline void TSLightenPreviewPageView(NSView *child, NSArray *filters) {
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    if (child.appearance != light) child.appearance = light;
    BOOL page = [NSStringFromClass(child.class) containsString:@"Page"];
    NSArray *wanted = page ? @[] : filters;
    if (child.contentFilters.count != wanted.count) child.contentFilters = wanted;
    if (page) TSPreparePreviewPageLayers(child, filters);
}
static inline void TSLightenPreviewPages(NSView *documentView, NSArray *filters) {
    for (NSView *child in documentView.subviews) TSLightenPreviewPageView(child, filters);
}

static void TSInstallPreviewPageHook(NSView *documentView);

// The selection effect layers are made with the page view and prepared when it is added.
// As a safeguard, should PDFKit make one later, a PDF view of a preview prepares its page
// views again when its selection changes, at once and once more after PDFKit has updated
// its layers. The method is added to PDFView once; the
// observer is removed when the PDF view is released.
static void TSPreviewSelectionChanged(__unsafe_unretained PDFView *self, SEL _cmd, NSNotification *note) {
    (void)_cmd; (void)note;
    __weak PDFView *weakView = self;
    void (^prepare)(void) = ^{
        PDFView *view = weakView;
        if (!view) return;
        NSArray *filters = TSPreviewPagesInverted(view) ? TSPreviewInversionFilters() : @[];
        for (NSView *child in view.documentView.subviews)
            if ([NSStringFromClass(child.class) containsString:@"Page"]) TSPreparePreviewPageLayers(child, filters);
    };
    prepare();
    dispatch_async(dispatch_get_main_queue(), prepare);
}
static inline void TSWatchPreviewSelection(PDFView *pdfView) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        class_addMethod(PDFView.class, sel_getUid("tsPreviewSelectionChanged:"), (IMP)TSPreviewSelectionChanged, "v@:@");
    });
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:pdfView name:PDFViewSelectionChangedNotification object:pdfView];
    [center addObserver:pdfView selector:sel_getUid("tsPreviewSelectionChanged:") name:PDFViewSelectionChangedNotification object:pdfView];
}

// A knob takes its color from the system. In Dark Mode that knob is light, and on a light
// page it is white on white. Preview.app draws a gray knob on a light page (macOS 27 Dark,
// the knob about 155,155,155). The same light knob on a legacy track is nearly the color of
// the light gutter beside the page (measured on macOS 26 Dark: knob 244 on track 230). The
// knob follows the pages, overlay or legacy: dark while they are light, light while they
// are inverted.
static inline BOOL TSPreviewFullScreenChromeIsDark(NSView *view) {
    return view.window != nil && objc_getAssociatedObject(view.window, TSPreviewFullScreenDarkKey) != nil;
}

static inline void TSPreviewMatchScrollerKnob(NSScrollView *scrollView, BOOL invert) {
    NSScrollerKnobStyle style = invert ? NSScrollerKnobStyleLight : NSScrollerKnobStyleDark;
    scrollView.scrollerKnobStyle = style;
    scrollView.verticalScroller.knobStyle = style;
    scrollView.horizontalScroller.knobStyle = style;
}

// Share the same PDF page treatment between the document and Experiment previews.
// Scroll bars take no explicit appearance and no filters. Their knob is chosen by
// TSPreviewMatchScrollerKnob. On macOS 27 an overlay scroller's effective appearance
// copies the clip view and the document view, so those two take no appearance and no
// filters. The pages are inverted as they are drawn. The gutter around the pages is
// drawn light and inverted by the filters on its view, which PDFKit does not magnify.
// The pocket stays unset so the title bar is not pulled off the system appearance.
static inline void TSApplyPreviewInversion(NSScrollView *scrollView, BOOL invert) {
    if (!scrollView) return;
    scrollView.appearance = nil;
    // Filters on the scroll view would also invert the pocket under the toolbar.
    scrollView.contentFilters = @[];
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSArray *filters = invert ? TSPreviewInversionFilters() : @[];
    for (NSView *subview in scrollView.subviews) {
        // The band above the first page paints the window color. Aqua or a filter here
        // would lighten that band and the toolbar with it.
        if ([NSStringFromClass(subview.class) containsString:@"TSPreviewToolbarShield"]) {
            subview.appearance = nil;
            subview.contentFilters = @[];
            continue;
        }
        if (TSPreviewSubviewIsToolbarPocket(subview) ||
            [subview isKindOfClass:[NSScroller class]] ||
            subview == scrollView.contentView) {
            // Scroll bars, the clip, and the pocket. Aqua on the clip is copied
            // onto an overlay scroller, so the bar would leave the system appearance.
            subview.appearance = nil;
            subview.contentFilters = @[];
            continue;
        }
        // Full screen keeps this view on the dark window. The pages stay as they were.
        // An inverted preview still draws the view light and inverts it: clearing the
        // appearance as well would invert the dark view back toward light.
        if (TSPreviewFullScreenChromeIsDark(scrollView) && !invert) {
            subview.appearance = nil;
            subview.contentFilters = @[];
        } else {
            subview.appearance = light;
            subview.contentFilters = filters;
        }
    }
    NSView *documentView = scrollView.documentView;
    documentView.appearance = nil;
    documentView.contentFilters = @[];
    TSInstallPreviewPageHook(documentView);
    TSLightenPreviewPages(documentView, filters);
    TSPreviewMatchScrollerKnob(scrollView, invert);
    objc_setAssociatedObject(scrollView, TSPreviewInversionStateKey, @(invert),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // The PDF view the scroll view belongs to draws its pages inverted or not; when that
    // changes, its pages are drawn again.
    NSView *pdfView = scrollView.superview;
    while (pdfView && ![pdfView isKindOfClass:PDFView.class]) pdfView = pdfView.superview;
    if (pdfView) TSWatchPreviewSelection((PDFView *)pdfView);
    if (pdfView && TSPreviewPagesInverted(pdfView) != invert) {
        objc_setAssociatedObject(pdfView, TSPreviewPagesInvertedKey, @(invert), OBJC_ASSOCIATION_RETAIN);
        [pdfView setNeedsDisplay:YES];
        for (NSView *child in documentView.subviews) [child setNeedsDisplay:YES];
    }
}

// Applies the choice again, as after -setDocument:, which puts a new document view in.
static inline void TSReapplyPreviewInversion(NSScrollView *scrollView) {
    NSNumber *invert = objc_getAssociatedObject(scrollView, TSPreviewInversionStateKey);
    if (!invert) return;
    TSApplyPreviewInversion(scrollView, invert.boolValue);
}

// While a preview window is in full screen its appearance is dark, including when the
// system is light. Scroll views that already follow the preview choice are told again,
// so the area around a light page follows that dark window. Pages are not inverted by
// this. Leaving full screen clears the appearance and tells those scroll views again.
static void TSPreviewReapplyFullScreenInView(NSView *view) {
    if ([view isKindOfClass:NSScrollView.class]) {
        NSNumber *invert = objc_getAssociatedObject(view, TSPreviewInversionStateKey);
        if (invert)
            TSApplyPreviewInversion((NSScrollView *)view, invert.boolValue);
    }
    NSArray<NSView *> *subviews = [view.subviews copy];
    for (NSView *subview in subviews)
        TSPreviewReapplyFullScreenInView(subview);
}

static inline void TSPreviewUseDarkFullScreenChrome(NSWindow *window, BOOL dark) {
    if (!window) return;
    objc_setAssociatedObject(window, TSPreviewFullScreenDarkKey, dark ? @YES : nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.appearance = dark ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : nil;
    if (window.contentView)
        TSPreviewReapplyFullScreenInView(window.contentView);
}

// A page view PDFKit adds while scrolling, or after a new document or display format, is
// made light the moment PDFKit adds it to the document view: -didAddSubview: of the
// document view's class calls the original method and then lightens the new view, when
// the view belongs to a preview (its scroll view carries the choice). Each class that
// gets the hook gets its own implementation, which holds that class's original, so a
// subclass and its superclass can both be hooked without either reaching the other's
// hook as its original. A class is left alone only when the implementation it actually
// inherits is one of these hooks; an override in between is hooked over, so the page view
// is made light after that override has run. The hooks are listed on NSView, so every
// file that includes this header sees the same list. When PDFKit's class is not the
// usual one, nothing changes but the hook: the pages are still inverted as they are drawn.
static void TSInstallPreviewPageHook(NSView *documentView) {
    Class cls = [documentView class];
    if (!cls || cls == NSView.class) return;
    SEL sel = @selector(didAddSubview:);
    @synchronized (NSView.class) {
        if (objc_getAssociatedObject(cls, sel_getUid("tsPreviewPageHook"))) return;
        Method own = NULL;
        unsigned count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned i = 0; i < count; i++) if (method_getName(methods[i]) == sel) own = methods[i];
        free(methods);
        NSMutableSet<NSValue *> *hooks = objc_getAssociatedObject(NSView.class, sel_getUid("tsPreviewPageHooks"));
        if (!hooks) {
            hooks = [NSMutableSet set];
            objc_setAssociatedObject(NSView.class, sel_getUid("tsPreviewPageHooks"), hooks, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        IMP original = own ? method_getImplementation(own)
                           : class_getMethodImplementation(class_getSuperclass(cls), sel);
        if (!own && [hooks containsObject:[NSValue valueWithPointer:(const void *)original]]) return;
        IMP hook = imp_implementationWithBlock(^(__unsafe_unretained NSView *view, NSView *subview) {
            ((void (*)(__unsafe_unretained id, SEL, NSView *))original)(view, sel, subview);
            NSNumber *invert = objc_getAssociatedObject(view.enclosingScrollView, TSPreviewInversionStateKey);
            if (invert)
                TSLightenPreviewPageView(subview, invert.boolValue ? TSPreviewInversionFilters() : @[]);
        });
        [hooks addObject:[NSValue valueWithPointer:(const void *)hook]];
        if (own) method_setImplementation(own, hook);
        else class_addMethod(cls, sel, hook, "v@:@");
        objc_setAssociatedObject(cls, sel_getUid("tsPreviewPageHook"), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// -setDocument: puts a new document view in. The choice is applied to it at once, while it
// has no page views yet, so they are made light as they come. The document preview and the Experiment preview set their documents through this.
static inline void TSPreviewSetDocument(PDFView *view, void (NS_NOESCAPE ^set)(void)) {
    set();
    TSInstallPreviewPageHook(view.documentView);
    TSReapplyPreviewInversion(view.documentView.enclosingScrollView);
}
