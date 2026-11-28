// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSAnnotationBar.m
 */

#import "TSAnnotationBar.h"
#import "TSAnnotationTextPopover.h"

static const CGFloat TSAnnotationBarHeight = 36;
static const CGFloat TSAnnotationBarToolSize = 29;
static const CGFloat TSAnnotationBarToolHeight = 28;
// The pictures are drawn on a 20 x 16 sheet and scaled up by this factor.
static const CGFloat TSAnnotationPictureScale = 1.25;
// On macOS 26 and later the controls sit on pieces of glass, grouped as in the toolbar above.
static const CGFloat TSAnnotationGlassHeight = 32;
static const CGFloat TSAnnotationGlassInset = 6;
static const CGFloat TSAnnotationGlassGap = 8;

// The parts of the Preview answer with the annotation selected for editing, and take the
// actions the bar sends them (MyPDFKitView-Annotations.m).
@protocol TSAnnotationSelecting
- (nullable PDFAnnotation *)selectedAnnotationForEditing;
@optional
- (void)strikeoutAnnotation:(nullable id)sender;
- (void)highlightAnnotation:(nullable id)sender;
- (void)underlineAnnotation:(nullable id)sender;
- (void)squareAnnotation:(nullable id)sender;
- (void)bsquareAnnotation:(nullable id)sender;
- (void)circleAnnotation:(nullable id)sender;
- (void)bcircleAnnotation:(nullable id)sender;
- (void)arrowAnnotation:(nullable id)sender;
- (void)textAnnotation:(nullable id)sender;
- (void)btextAnnotation:(nullable id)sender;
- (void)popupAnnotation:(nullable id)sender;
- (void)showColorPanel:(nullable id)sender;
- (void)showFontPanel:(nullable id)sender;
- (void)removeStreams:(nullable id)sender;
- (void)saveAnnotations:(nullable id)sender;
@end

static const NSUInteger TSAnnotationToolsCount = 11;

NSUInteger TSAnnotationToolCount(void)
{
    return TSAnnotationToolsCount;
}

TSAnnotationTool TSAnnotationToolAtIndex(NSUInteger index)
{
    switch (index) {
        case 0: return (TSAnnotationTool){ @selector(strikeoutAnnotation:), @"Strikeout" };
        case 1: return (TSAnnotationTool){ @selector(highlightAnnotation:), @"Highlight" };
        case 2: return (TSAnnotationTool){ @selector(underlineAnnotation:), @"Underline" };
        case 3: return (TSAnnotationTool){ @selector(squareAnnotation:), @"Square" };
        case 4: return (TSAnnotationTool){ @selector(bsquareAnnotation:), @"Bordered Square" };
        case 5: return (TSAnnotationTool){ @selector(circleAnnotation:), @"Circle" };
        case 6: return (TSAnnotationTool){ @selector(bcircleAnnotation:), @"Bordered Circle" };
        case 7: return (TSAnnotationTool){ @selector(arrowAnnotation:), @"Arrow" };
        case 8: return (TSAnnotationTool){ @selector(textAnnotation:), @"Text" };
        case 9: return (TSAnnotationTool){ @selector(btextAnnotation:), @"Bordered Text" };
        default: return (TSAnnotationTool){ @selector(popupAnnotation:), @"Popup" };
    }
}

// The names of the tools, as the annotation menu of the Preview shows them.
static NSString *TSAnnotationToolName(NSUInteger index)
{
    switch (index) {
        case 0: return NSLocalizedString(@"Strikeout", @"Annotation tool");
        case 1: return NSLocalizedString(@"Highlight", @"Annotation tool");
        case 2: return NSLocalizedString(@"Underline", @"Annotation tool");
        case 3: return NSLocalizedString(@"Square", @"Annotation tool");
        case 4: return NSLocalizedString(@"Bordered Square", @"Annotation tool");
        case 5: return NSLocalizedString(@"Circle", @"Annotation tool");
        case 6: return NSLocalizedString(@"Bordered Circle", @"Annotation tool");
        case 7: return NSLocalizedString(@"Arrow", @"Annotation tool");
        case 8: return NSLocalizedString(@"Text Annotation", @"Annotation tool: text without a background");
        case 9: return NSLocalizedString(@"Bordered Text", @"Annotation tool");
        default: return NSLocalizedString(@"Popup", @"Annotation tool");
    }
}

#pragma mark - Pictures

// The colors of the pictures keep the hues of the annotations they make, and come in a light
// and a dark value, so that each stands out from the gray of the bar in either appearance.
static NSColor *TSAnnotationPictureColor(CGFloat lr, CGFloat lg, CGFloat lb, CGFloat dr, CGFloat dg, CGFloat db)
{
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
        return dark ? [NSColor colorWithSRGBRed:dr green:dg blue:db alpha:1] : [NSColor colorWithSRGBRed:lr green:lg blue:lb alpha:1];
    }];
}

// The picture of a tool, drawn in the colors the tool gives a new annotation.
static NSImage *TSAnnotationToolImage(NSUInteger index, NSString *name)
{
    NSImage *image = [NSImage imageWithSize:NSMakeSize(ceil(20 * TSAnnotationPictureScale), ceil(16 * TSAnnotationPictureScale)) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSAffineTransform *scale = [NSAffineTransform transform];
        [scale scaleBy:TSAnnotationPictureScale];
        [scale concat];
        NSColor *ink = NSColor.labelColor;
        NSColor *red = TSAnnotationPictureColor(0.85, 0.10, 0.10, 1.00, 0.42, 0.40);
        NSColor *green = TSAnnotationPictureColor(0.00, 0.58, 0.10, 0.30, 0.95, 0.38);
        // Where black text or lines lie on the green, the green is a light one.
        NSColor *greenFill = TSAnnotationPictureColor(0.38, 0.86, 0.38, 0.30, 0.95, 0.38);
        NSColor *purple = TSAnnotationPictureColor(0.45, 0.12, 0.60, 0.80, 0.55, 1.00);
        // The letters of the pictures, in the system's serif design, as text in a page.
        NSFontDescriptor *serifDesign = [[NSFont systemFontOfSize:13].fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignSerif];
        NSFont *serifFont = (serifDesign ? [NSFont fontWithDescriptor:serifDesign size:13] : nil) ?: [NSFont systemFontOfSize:13];
        NSDictionary *serif = @{NSFontAttributeName: serifFont, NSForegroundColorAttributeName: ink};
        NSBezierPath *path;
        switch (index) {
            case 0: // strikeout
                [@"S" drawAtPoint:NSMakePoint(5, 0) withAttributes:serif];
                [red setStroke];
                path = [NSBezierPath bezierPath];
                [path moveToPoint:NSMakePoint(2, 7.5)]; [path lineToPoint:NSMakePoint(16, 7.5)];
                path.lineWidth = 1.6; [path stroke];
                break;
            case 1: { // highlight
                [[NSColor colorWithSRGBRed:1 green:1 blue:0.43 alpha:1] setFill];
                NSRectFill(NSMakeRect(2, 2, 16, 12));
                NSMutableDictionary *black = [serif mutableCopy];
                black[NSForegroundColorAttributeName] = NSColor.blackColor;
                [@"E" drawAtPoint:NSMakePoint(5, 0) withAttributes:black];
                break;
            }
            case 2: // underline
                [@"U" drawAtPoint:NSMakePoint(5, 2) withAttributes:serif];
                [red setStroke];
                path = [NSBezierPath bezierPath];
                [path moveToPoint:NSMakePoint(3, 2)]; [path lineToPoint:NSMakePoint(17, 2)];
                path.lineWidth = 1.6; [path stroke];
                break;
            case 3:
                [ink setStroke];
                path = [NSBezierPath bezierPathWithRect:NSMakeRect(3.5, 3.5, 13, 9)];
                path.lineWidth = 1.3; [path stroke];
                break;
            case 4:
                [green setStroke];
                path = [NSBezierPath bezierPathWithRect:NSMakeRect(4.5, 4.5, 11, 7)];
                path.lineWidth = 3; [path stroke];
                break;
            case 5:
                [ink setStroke];
                path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(2.5, 3.5, 15, 9)];
                path.lineWidth = 1.3; [path stroke];
                break;
            case 6:
                [green setStroke];
                path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3.5, 4, 13, 8)];
                path.lineWidth = 3; [path stroke];
                break;
            case 7: // arrow
                [purple setStroke];
                path = [NSBezierPath bezierPath];
                [path moveToPoint:NSMakePoint(4, 2)]; [path lineToPoint:NSMakePoint(15, 13)];
                [path moveToPoint:NSMakePoint(9, 13)]; [path lineToPoint:NSMakePoint(15, 13)]; [path lineToPoint:NSMakePoint(15, 7)];
                path.lineWidth = 2; [path stroke];
                break;
            case 8:
            case 9: {
                if (index == 9) {
                    [greenFill setFill];
                    NSRectFill(NSMakeRect(1, 1, 18, 14));
                }
                NSDictionary *sans = @{NSFontAttributeName: [NSFont systemFontOfSize:12],
                                       NSForegroundColorAttributeName: index == 9 ? NSColor.blackColor : red};
                [@"Hi" drawAtPoint:NSMakePoint(3, 1) withAttributes:sans];
                break;
            }
            default: { // popup
                path = [NSBezierPath bezierPath];
                [path moveToPoint:NSMakePoint(2, 14)]; [path lineToPoint:NSMakePoint(18, 14)];
                [path lineToPoint:NSMakePoint(18, 5)]; [path lineToPoint:NSMakePoint(8, 5)];
                [path lineToPoint:NSMakePoint(4, 1)]; [path lineToPoint:NSMakePoint(4, 5)];
                [path lineToPoint:NSMakePoint(2, 5)]; [path closePath];
                [greenFill setFill]; [path fill];
                [NSColor.blackColor setStroke]; path.lineWidth = 1; [path stroke];
                path = [NSBezierPath bezierPath];
                [path moveToPoint:NSMakePoint(5, 11)]; [path lineToPoint:NSMakePoint(15, 11)];
                [path moveToPoint:NSMakePoint(5, 8)]; [path lineToPoint:NSMakePoint(15, 8)];
                path.lineWidth = 1; [path stroke];
                break;
            }
        }
        return YES;
    }];
    image.accessibilityDescription = name;
    return image;
}

static NSImage *TSAnnotationSymbol(NSString *symbol, NSString *description)
{
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:description];
    NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightMedium];
    return [image imageWithSymbolConfiguration:size] ?: [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
}

static NSButton *TSAnnotationIconButton(NSImage *image, NSString *name, id target, SEL action)
{
    // A button without a border, as in the bar under a list. A recessed button would draw the
    // picture as a template, in gray, and the colors tell the tools apart.
    NSButton *button = [NSButton buttonWithImage:image target:target action:action];
    button.bordered = NO;
    button.imageScaling = NSImageScaleNone;
    button.toolTip = name;
    button.accessibilityLabel = name;
    [button.widthAnchor constraintEqualToConstant:TSAnnotationBarToolSize].active = YES;
    [button.heightAnchor constraintEqualToConstant:TSAnnotationBarToolHeight].active = YES;
    return button;
}

static NSView *TSAnnotationSeparator(void)
{
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 1, 18)];
    box.boxType = NSBoxSeparator;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box.widthAnchor constraintEqualToConstant:1].active = YES;
    [box.heightAnchor constraintEqualToConstant:18].active = YES;
    return box;
}

static BOOL TSAnnotationBarUsesGlass(void)
{
    if (@available(macOS 26.0, *))
        return YES;
    return NO;
}

// A row of controls side by side.
static NSStackView *TSAnnotationRow(NSArray<NSView *> *views, CGFloat spacing)
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    stack.detachesHiddenViews = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

// A group of controls. On glass it is one piece of glass, like a group of items in the
// toolbar, and the pages scrolling under the bar show blurred around it.
static NSView *TSAnnotationGroup(NSArray<NSView *> *views, CGFloat spacing)
{
    NSStackView *stack = TSAnnotationRow(views, spacing);
    if (@available(macOS 26.0, *)) {
        stack.edgeInsets = NSEdgeInsetsMake(0, TSAnnotationGlassInset, 0, TSAnnotationGlassInset);
        NSGlassEffectView *glass = [[NSGlassEffectView alloc] init];
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        glass.cornerRadius = TSAnnotationGlassHeight / 2;
        glass.contentView = stack;
        [glass.heightAnchor constraintEqualToConstant:TSAnnotationGlassHeight].active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:glass.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:glass.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:glass.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:glass.bottomAnchor],
        ]];
        return glass;
    }
    return stack;
}

static BOOL TSIsSharedPanel(NSWindow *window)
{
    return [window isKindOfClass:NSColorPanel.class] || [window isKindOfClass:NSFontPanel.class];
}

#pragma mark -

@interface TSAnnotationBarView : NSView
@property (nonatomic, weak) TSAnnotationBar *bar;
@end

@implementation TSAnnotationBarView
- (void)layout
{
    [super layout];
    [self.bar layoutForWidth:NSWidth(self.bounds)];
}
@end

@interface TSAnnotationBar () <NSMenuDelegate, NSMenuItemValidation>
@end

@implementation TSAnnotationBar {
    __weak id<TSAnnotationBarHost> _host;
    __weak NSWindow *_attachedWindow;
    CGFloat _windowMinContentWidth;
    NSStackView *_stack;
    NSArray<NSView *> *_fullOnly;   // shown only when everything fits
    NSView *_fullSpacerSeparator;
    BOOL _compact;
    CGFloat _fullWidth, _compactWidth;
    TSAnnotationTextPopover *_textPopover;
    NSButton *_editModeButton, *_colorButton, *_fontButton, *_textButton, *_saveButton, *_saveAllCheckBox, *_closeButton;
    NSPopUpButton *_moreButton, *_overflowButton;
    NSArray<NSButton *> *_toolButtons;
    BOOL _ownsColorPanel, _ownsFontPanel;
    BOOL _observingFirstResponder;
}

@synthesize host = _host, attachedWindow = _attachedWindow, textPopover = _textPopover, compact = _compact;
@synthesize fullWidth = _fullWidth, compactWidth = _compactWidth, editModeButton = _editModeButton, toolButtons = _toolButtons;
@synthesize colorButton = _colorButton, fontButton = _fontButton, textButton = _textButton, moreButton = _moreButton;
@synthesize saveButton = _saveButton, saveAllCheckBox = _saveAllCheckBox, overflowButton = _overflowButton, closeButton = _closeButton;
@synthesize ownsColorPanel = _ownsColorPanel, ownsFontPanel = _ownsFontPanel;

- (instancetype)initWithHost:(id<TSAnnotationBarHost>)host
{
    if (!(self = [super initWithNibName:nil bundle:nil]))
        return nil;
    _host = host;
    _textPopover = [[TSAnnotationTextPopover alloc] init];
    self.layoutAttribute = NSLayoutAttributeBottom;
    // The pages scroll on under the bar with the soft edge of the toolbar: they show blurred
    // around the pieces of glass, and the icons stay on the glass, clear of a heading behind.
    [self view];
    return self;
}

- (void)loadView
{
    TSAnnotationBarView *view = [[TSAnnotationBarView alloc] initWithFrame:NSMakeRect(0, 0, 800, TSAnnotationBarHeight)];
    view.bar = self;
    view.identifier = @"TSAnnotationBar";

    NSString *editName = NSLocalizedString(@"Edit Mode", @"Annotation toolbar: switch for edit mode");
    _editModeButton = [NSButton buttonWithTitle:editName image:TSAnnotationSymbol(@"pencil", editName) target:self action:@selector(toggleEditMode:)];
    [_editModeButton setButtonType:NSButtonTypePushOnPushOff];
    _editModeButton.bezelStyle = NSBezelStyleRounded;
    _editModeButton.imagePosition = NSImageLeading;
    _editModeButton.toolTip = editName;
    _editModeButton.accessibilityLabel = editName;
    _editModeButton.controlSize = NSControlSizeRegular;

    NSMutableArray<NSButton *> *tools = [NSMutableArray array];
    for (NSUInteger i = 0; i < TSAnnotationToolCount(); i++) {
        NSString *name = TSAnnotationToolName(i);
        NSButton *button = TSAnnotationIconButton(TSAnnotationToolImage(i, name), name, self, @selector(useTool:));
        button.tag = (NSInteger)i;
        [tools addObject:button];
    }
    _toolButtons = tools;

    NSString *colorsName = NSLocalizedString(@"Show Colors", @"Annotation toolbar: opens the color panel");
    NSString *fontsName = NSLocalizedString(@"Show Fonts", @"Annotation toolbar: opens the font panel");
    NSString *textName = NSLocalizedString(@"Edit Text…", @"Annotation toolbar: edits the text of a text annotation");
    _colorButton = TSAnnotationIconButton(TSAnnotationSymbol(@"paintpalette", colorsName), colorsName, self, @selector(showColors:));
    _fontButton = TSAnnotationIconButton(TSAnnotationSymbol(@"textformat", fontsName), fontsName, self, @selector(showFonts:));
    _textButton = TSAnnotationIconButton(TSAnnotationSymbol(@"text.bubble", textName), textName, self, @selector(editText:));

    NSString *moreName = NSLocalizedString(@"More", @"Annotation toolbar: menu of less used commands");
    _moreButton = [self pullDownWithSymbol:@"ellipsis.circle" name:moreName];
    [self addRemoveStreamsItemTo:_moreButton.menu];

    _saveButton = [NSButton buttonWithTitle:NSLocalizedString(@"Save Annotations…", @"Annotation toolbar: saves the annotated PDF")
                                     target:self action:@selector(saveAnnotations:)];
    _saveButton.bezelStyle = NSBezelStyleRounded;
    _saveAllCheckBox = [NSButton checkboxWithTitle:NSLocalizedString(@"All Pages", @"Annotation toolbar: Save Annotations saves every page")
                                            target:self action:@selector(toggleSaveAll:)];

    NSString *overflowName = NSLocalizedString(@"More", @"Annotation toolbar: menu of less used commands");
    _overflowButton = [self pullDownWithSymbol:@"chevron.right.2" name:overflowName];
    _overflowButton.menu.delegate = self;

    NSString *closeName = NSLocalizedString(@"Close Annotation Toolbar", @"Annotation toolbar: its close button");
    _closeButton = [NSButton buttonWithImage:TSAnnotationSymbol(@"xmark.circle.fill", closeName) target:self action:@selector(close:)];
    _closeButton.bordered = NO;
    _closeButton.contentTintColor = NSColor.secondaryLabelColor;
    _closeButton.toolTip = closeName;
    _closeButton.accessibilityLabel = closeName;

    NSView *spacer = [[NSView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // The groups of the bar, as its separators part them: text markup, shapes, the arrow,
    // text annotations, then color, font, text and more.
    NSArray<NSArray<NSView *> *> *toolGroups = @[[tools subarrayWithRange:NSMakeRange(0, 3)], [tools subarrayWithRange:NSMakeRange(3, 4)],
                                                 [tools subarrayWithRange:NSMakeRange(7, 1)], [tools subarrayWithRange:NSMakeRange(8, 3)]];
    NSArray<NSView *> *formatGroup = @[_colorButton, _fontButton, _textButton, _moreButton];
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:_editModeButton];
    BOOL glass = TSAnnotationBarUsesGlass();
    if (glass) {
        _saveButton.bezelStyle = NSBezelStyleGlass;
        for (NSArray<NSView *> *group in toolGroups)
            [views addObject:TSAnnotationGroup(group, 2)];
        NSView *format = TSAnnotationGroup(formatGroup, 2);
        // Save Annotations is a glass button itself, and close is a round button: they stand
        // on the bar without a piece of glass under them, which would draw a second outline.
        NSView *save = TSAnnotationRow(@[_saveButton, _saveAllCheckBox], 8);
        [views addObjectsFromArray:@[format, spacer, save, TSAnnotationRow(@[_overflowButton, _closeButton], 2)]];
        _fullOnly = @[format, save];
    } else {
        [views addObject:TSAnnotationSeparator()];
        for (NSArray<NSView *> *group in toolGroups) {
            if (group != toolGroups.firstObject)
                [views addObject:TSAnnotationSeparator()];
            [views addObjectsFromArray:group];
        }
        _fullSpacerSeparator = TSAnnotationSeparator();
        [views addObject:_fullSpacerSeparator];
        [views addObjectsFromArray:formatGroup];
        [views addObjectsFromArray:@[spacer, _saveButton, _saveAllCheckBox, _overflowButton, _closeButton]];
        _fullOnly = [@[_fullSpacerSeparator] arrayByAddingObjectsFromArray:[formatGroup arrayByAddingObjectsFromArray:@[_saveButton, _saveAllCheckBox]]];
    }

    _stack = [NSStackView stackViewWithViews:views];
    _stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _stack.alignment = NSLayoutAttributeCenterY;
    _stack.spacing = glass ? TSAnnotationGlassGap : 2;
    _stack.detachesHiddenViews = YES;
    _stack.edgeInsets = NSEdgeInsetsMake(0, 8, 0, 8);
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    // The full bar must not keep the window from getting narrower: when it does not fit,
    // the narrow layout takes over (see layoutForWidth:).
    [_stack setClippingResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    if (!glass) {
        [_stack setCustomSpacing:6 afterView:_editModeButton];
        [_stack setCustomSpacing:8 afterView:_saveButton];
        [_stack setCustomSpacing:6 afterView:_saveAllCheckBox];
    }
    [view addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_stack.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [view.heightAnchor constraintEqualToConstant:TSAnnotationBarHeight],
    ]];
    self.view = view;
    self.fullScreenMinHeight = TSAnnotationBarHeight;
    [self measureWidths];
    [self setCompact:NO];
    [self updateControls];
}

- (NSPopUpButton *)pullDownWithSymbol:(NSString *)symbol name:(NSString *)name
{
    NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 40, 24) pullsDown:YES];
    button.bordered = NO;
    button.toolTip = name;
    button.accessibilityLabel = name;
    NSMenuItem *title = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    title.image = TSAnnotationSymbol(symbol, name);
    [button.menu addItem:title];
    ((NSPopUpButtonCell *)button.cell).arrowPosition = NSPopUpNoArrow;
    button.imagePosition = NSImageOnly;
    [button.widthAnchor constraintEqualToConstant:TSAnnotationBarToolSize + 4].active = YES;
    return button;
}

- (void)addRemoveStreamsItemTo:(NSMenu *)menu
{
    NSMenuItem *item = [menu addItemWithTitle:NSLocalizedString(@"Remove Image Streams", @"Annotation toolbar: removes the image streams of the annotations")
                                       action:@selector(removeStreams:) keyEquivalent:@""];
    item.target = self;
}

#pragma mark Layout

- (void)setCompact:(BOOL)compact
{
    _compact = compact;
    for (NSView *view in _fullOnly)
        view.hidden = compact;
    _overflowButton.hidden = !compact;
    _editModeButton.imagePosition = compact ? NSImageOnly : NSImageLeading;
}

// The width each layout needs, in the current language.
- (void)measureWidths
{
    BOOL was = _compact;
    [self setCompact:NO];
    _fullWidth = ceil(_stack.fittingSize.width);
    [self setCompact:YES];
    _compactWidth = ceil(_stack.fittingSize.width);
    [self setCompact:was];
}

- (void)layoutForWidth:(CGFloat)width
{
    BOOL compact = width < _fullWidth;
    if (compact != _compact)
        [self setCompact:compact];
}

#pragma mark Attaching

- (void)attachToWindow:(NSWindow *)window
{
    if (_attachedWindow == window && self.parentViewController)
        return;
    [self detach];
    _attachedWindow = window;
    [window addTitlebarAccessoryViewController:self];
    // While the bar is shown the window is at least as wide as the narrowest bar. Only the
    // width is changed: AppKit works out the height of the minimum size with the bar itself.
    NSSize minSize = window.contentMinSize;
    _windowMinContentWidth = minSize.width;
    minSize.width = MAX(minSize.width, _compactWidth);
    window.contentMinSize = minSize;
    if (NSWidth(window.frame) < _compactWidth) {
        NSRect frame = window.frame;
        frame.size.width = _compactWidth;
        NSRect screen = window.screen.visibleFrame;
        if (!NSIsEmptyRect(screen) && NSMaxX(frame) > NSMaxX(screen))
            frame.origin.x = MAX(NSMinX(screen), NSMaxX(screen) - NSWidth(frame));
        [window setFrame:frame display:YES];
    }
    [self layoutForWidth:NSWidth(window.frame)];
    [self startObservingWindow:window];
    [self updateControls];
}

- (void)detach
{
    NSWindow *window = _attachedWindow;
    [_textPopover finishWithReason:TSAnnotationTextFinishDiscard];
    if (window) {
        [self stopObservingWindow:window];
        if (self.parentViewController || [window.titlebarAccessoryViewControllers containsObject:self]) {
            NSUInteger index = [window.titlebarAccessoryViewControllers indexOfObjectIdenticalTo:self];
            if (index != NSNotFound)
                [window removeTitlebarAccessoryViewControllerAtIndex:(NSInteger)index];
        }
        NSSize minSize = window.contentMinSize;
        minSize.width = _windowMinContentWidth;
        window.contentMinSize = minSize;
    }
    _attachedWindow = nil;
    _ownsColorPanel = _ownsFontPanel = NO;
}

- (void)startObservingWindow:(NSWindow *)window
{
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(windowDidUpdate:) name:NSWindowDidUpdateNotification object:window];
    [center addObserver:self selector:@selector(someWindowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:nil];
    [center addObserver:self selector:@selector(someWindowWillClose:) name:NSWindowWillCloseNotification object:nil];
    [window addObserver:self forKeyPath:@"firstResponder" options:0 context:(__bridge void *)self];
    _observingFirstResponder = YES;
}

- (void)stopObservingWindow:(NSWindow *)window
{
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self name:NSWindowDidUpdateNotification object:window];
    [center removeObserver:self name:NSWindowDidBecomeKeyNotification object:nil];
    [center removeObserver:self name:NSWindowWillCloseNotification object:nil];
    if (_observingFirstResponder)
        [window removeObserver:self forKeyPath:@"firstResponder" context:(__bridge void *)self];
    _observingFirstResponder = NO;
}

- (void)windowDidUpdate:(NSNotification *)notification
{
    [self updateControls];
}

#pragma mark Shared panels (spec §3.7)

// Another window became key: the color and font panels now serve it, not this document.
- (void)someWindowDidBecomeKey:(NSNotification *)notification
{
    NSWindow *window = notification.object;
    if (window == _attachedWindow || TSIsSharedPanel(window) || window == _textPopover.view.window)
        return;
    _ownsColorPanel = _ownsFontPanel = NO;
}

- (void)someWindowWillClose:(NSNotification *)notification
{
    NSWindow *window = notification.object;
    if ([window isKindOfClass:NSColorPanel.class])
        _ownsColorPanel = NO;
    else if ([window isKindOfClass:NSFontPanel.class])
        _ownsFontPanel = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != (__bridge void *)self) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    NSResponder *responder = ((NSWindow *)object).firstResponder;
    // The bar's own controls (with Full Keyboard Access) do not move the panels to another user.
    if ([responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:self.view])
        return;
    if (responder == object)
        return;
    if (![_host annotationViewBelongsToHost:responder])
        _ownsColorPanel = _ownsFontPanel = NO;
}

// Where the color and font panels send their changes now.
- (BOOL)sharedPanelsServeHost
{
    NSWindow *window = NSApp.keyWindow;
    if (window == nil || TSIsSharedPanel(window))
        window = NSApp.mainWindow;
    return window == _attachedWindow && [_host annotationViewBelongsToHost:window.firstResponder];
}

- (void)closeSharedPanelsIfOwned
{
    BOOL serve = [self sharedPanelsServeHost];
    if (_ownsColorPanel && serve && [NSColorPanel sharedColorPanelExists])
        [[NSColorPanel sharedColorPanel] close];
    if (_ownsFontPanel && serve && [NSFontPanel sharedFontPanelExists])
        [[NSFontPanel sharedFontPanel] close];
    _ownsColorPanel = _ownsFontPanel = NO;
}

#pragma mark Controls

- (PDFAnnotation *)selectedTextAnnotation
{
    PDFView *view = [_host annotationTargetView];
    if (!view || ![view respondsToSelector:@selector(selectedAnnotationForEditing)])
        return nil;
    PDFAnnotation *annotation = [(id<TSAnnotationSelecting>)view selectedAnnotationForEditing];
    return [TSAnnotationTextPopover canEditAnnotation:annotation] ? annotation : nil;
}

- (void)updateControls
{
    id<TSAnnotationBarHost> host = _host;
    BOOL edit = host.annotationEditMode;
    _editModeButton.state = edit ? NSControlStateValueOn : NSControlStateValueOff;
    _editModeButton.accessibilityValue = @(edit);
    for (NSButton *button in _toolButtons)
        button.enabled = edit;
    _colorButton.enabled = edit;
    _fontButton.enabled = edit;
    _textButton.enabled = edit && (_textPopover.shown || [self selectedTextAnnotation] != nil);
    _saveAllCheckBox.state = host.annotationSaveAllPages ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleEditMode:(id)sender
{
    [_host setAnnotationEditMode:_editModeButton.state == NSControlStateValueOn];
    [self updateControls];
}

- (void)useTool:(NSButton *)sender
{
    NSUInteger index = (NSUInteger)sender.tag;
    if (!_host.annotationEditMode || index >= TSAnnotationToolCount())
        return;
    [_host performAnnotationCommand:TSAnnotationToolAtIndex(index).action];
}

- (void)showColors:(id)sender
{
    if (!_host.annotationEditMode)
        return;
    [_host performAnnotationCommand:@selector(showColorPanel:)];
    PDFView *view = [_host annotationTargetView];
    PDFAnnotation *annotation = [view respondsToSelector:@selector(selectedAnnotationForEditing)] ? [(id<TSAnnotationSelecting>)view selectedAnnotationForEditing] : nil;
    if (annotation.color)
        [NSColorPanel sharedColorPanel].color = annotation.color;
    _ownsColorPanel = YES;
}

- (void)showFonts:(id)sender
{
    if (!_host.annotationEditMode)
        return;
    [_host performAnnotationCommand:@selector(showFontPanel:)];
    _ownsFontPanel = YES;
}

- (void)editText:(id)sender
{
    if (_textPopover.shown) {
        [_textPopover finishWithReason:TSAnnotationTextFinishCommit];
        [self updateControls];
        return;
    }
    PDFAnnotation *annotation = [self selectedTextAnnotation];
    PDFView *view = [_host annotationTargetView];
    if (!_host.annotationEditMode || !annotation || !view)
        return;
    NSView *anchor = _compact ? _overflowButton : _textButton;
    [_textPopover showForAnnotation:annotation inView:view relativeToView:anchor];
}

- (void)removeStreams:(id)sender
{
    [_host performAnnotationCommand:@selector(removeStreams:)];
}

- (void)saveAnnotations:(id)sender
{
    [_host performAnnotationCommand:@selector(saveAnnotations:)];
}

- (void)toggleSaveAll:(id)sender
{
    if ([sender isKindOfClass:NSMenuItem.class])
        _host.annotationSaveAllPages = !_host.annotationSaveAllPages;
    else
        _host.annotationSaveAllPages = _saveAllCheckBox.state == NSControlStateValueOn;
    [self updateControls];
}

- (void)close:(id)sender
{
    [_host hideAnnotationBar];
}

// The menu of » holds what does not fit, in the order of the full bar.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu != _overflowButton.menu)
        return;
    while (menu.numberOfItems > 1)
        [menu removeItemAtIndex:1];
    BOOL edit = _host.annotationEditMode;
    NSMenuItem *item;
    item = [menu addItemWithTitle:_colorButton.toolTip ?: @"" action:edit ? @selector(showColors:) : NULL keyEquivalent:@""];
    item.target = self;
    item = [menu addItemWithTitle:_fontButton.toolTip ?: @"" action:edit ? @selector(showFonts:) : NULL keyEquivalent:@""];
    item.target = self;
    item = [menu addItemWithTitle:_textButton.toolTip ?: @"" action:_textButton.enabled ? @selector(editText:) : NULL keyEquivalent:@""];
    item.target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    [self addRemoveStreamsItemTo:menu];
    [menu addItem:[NSMenuItem separatorItem]];
    item = [menu addItemWithTitle:_saveButton.title action:@selector(saveAnnotations:) keyEquivalent:@""];
    item.target = self;
    item = [menu addItemWithTitle:_saveAllCheckBox.title action:@selector(toggleSaveAll:) keyEquivalent:@""];
    item.target = self;
    item.state = _host.annotationSaveAllPages ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    return item.action != NULL;
}

- (void)dealloc
{
    NSWindow *window = _attachedWindow;
    if (window)
        [self stopObservingWindow:window];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
