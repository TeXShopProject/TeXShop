// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSAnnotationTextPopover.m
 */

#import "TSAnnotationTextPopover.h"

@interface TSAnnotationTextPopover () <NSPopoverDelegate, NSTextViewDelegate>
@end

@implementation TSAnnotationTextPopover {
    NSPopover *_popover;
    id _monitor;
    __weak PDFView *_boundView;
    __weak PDFAnnotation *_boundAnnotation;
    __weak PDFDocument *_boundDocument;
    NSString *_shownText;
    NSTextAlignment _shownAlignment;
    BOOL _finished;
    BOOL _commitScheduled;
    NSTextView *_textView;
    NSSegmentedControl *_alignmentControl;
    NSButton *_okButton;
}

+ (BOOL)canEditAnnotation:(PDFAnnotation *)annotation
{
    NSString *type = annotation.type;
    if (type.length == 0)
        return NO;
    return [[@"/" stringByAppendingString:type] isEqualToString:PDFAnnotationSubtypeFreeText];
}

- (instancetype)init
{
    return [super initWithNibName:nil bundle:nil];
}

- (void)loadView
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 260, 80)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _textView = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    // The contents of an annotation are a plain string: one alignment for the whole text.
    _textView.richText = NO;
    _textView.importsGraphics = NO;
    _textView.allowsUndo = YES;
    _textView.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    _textView.autoresizingMask = NSViewWidthSizable;
    _textView.minSize = NSMakeSize(0, 0);
    _textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _textView.verticallyResizable = YES;
    _textView.textContainer.widthTracksTextView = YES;
    _textView.delegate = self;
    scroll.documentView = _textView;

    _alignmentControl = [NSSegmentedControl segmentedControlWithLabels:@[NSLocalizedString(@"Left", @"Alignment of the text of an annotation"),
                                                                          NSLocalizedString(@"Center", @"Alignment of the text of an annotation"),
                                                                          NSLocalizedString(@"Right", @"Alignment of the text of an annotation")]
                                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                target:self action:@selector(alignmentChanged:)];
    _alignmentControl.controlSize = NSControlSizeSmall;
    _alignmentControl.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
    _alignmentControl.translatesAutoresizingMaskIntoConstraints = NO;

    _okButton = [NSButton buttonWithTitle:NSLocalizedString(@"OK", @"OK") target:self action:@selector(ok:)];
    _okButton.keyEquivalent = @"\r";
    _okButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    _okButton.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 132)];
    [view addSubview:scroll];
    [view addSubview:_alignmentControl];
    [view addSubview:_okButton];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:view.topAnchor constant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
        [scroll.heightAnchor constraintEqualToConstant:80],
        [scroll.widthAnchor constraintGreaterThanOrEqualToConstant:260],
        [_alignmentControl.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:10],
        [_alignmentControl.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [_alignmentControl.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-12],
        [_okButton.centerYAnchor constraintEqualToAnchor:_alignmentControl.centerYAnchor],
        [_okButton.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [_okButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:_alignmentControl.trailingAnchor constant:12],
    ]];
    self.view = view;
}

- (NSTextView *)textView { [self view]; return _textView; }
- (NSSegmentedControl *)alignmentControl { [self view]; return _alignmentControl; }
- (NSButton *)okButton { [self view]; return _okButton; }
- (PDFView *)boundView { return _boundView; }
- (PDFAnnotation *)boundAnnotation { return _boundAnnotation; }
- (BOOL)shown { return _popover != nil && !_finished; }

static NSInteger TSSegmentForAlignment(NSTextAlignment alignment)
{
    switch (alignment) {
        case NSTextAlignmentLeft: return 0;
        case NSTextAlignmentRight: return 2;
        default: return 1;
    }
}

static NSTextAlignment TSAlignmentForSegment(NSInteger segment)
{
    switch (segment) {
        case 0: return NSTextAlignmentLeft;
        case 2: return NSTextAlignmentRight;
        default: return NSTextAlignmentCenter;
    }
}

- (void)showForAnnotation:(PDFAnnotation *)annotation inView:(PDFView *)view relativeToView:(NSView *)anchor
{
    if (self.shown)
        [self finishWithReason:TSAnnotationTextFinishCommit];
    [self view];
    _boundView = view;
    _boundAnnotation = annotation;
    _boundDocument = view.document;
    _finished = NO;
    _commitScheduled = NO;
    // The field is filled here only; nothing writes into it while it is open.
    _shownText = annotation.contents ?: @"";
    _shownAlignment = annotation.alignment;
    _textView.string = _shownText;
    _textView.alignment = _shownAlignment;
    _alignmentControl.selectedSegment = TSSegmentForAlignment(_shownAlignment);
    [_textView.undoManager removeAllActions];

    _popover = [[NSPopover alloc] init];
    // Not transient: AppKit would close it on a click before that click's action decides
    // whether the text is kept.
    _popover.behavior = NSPopoverBehaviorApplicationDefined;
    _popover.contentViewController = self;
    _popover.delegate = self;
    if (anchor.window)
        [_popover showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
    [self.view.window makeFirstResponder:_textView];
    [_textView selectAll:nil];
    [self startMonitor];
}

- (void)startMonitor
{
    [self stopMonitor];
    __weak TSAnnotationTextPopover *weakSelf = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown
                                                     handler:^NSEvent *(NSEvent *event) {
        TSAnnotationTextPopover *strongSelf = weakSelf;
        if (strongSelf && strongSelf.shown && event.window != strongSelf.view.window)
            [strongSelf noteOutsideClick];
        return event;
    }];
}

- (void)stopMonitor
{
    if (_monitor)
        [NSEvent removeMonitor:_monitor];
    _monitor = nil;
}

- (void)noteOutsideClick
{
    if (!self.shown || _commitScheduled)
        return;
    _commitScheduled = YES;
    // Runs only in the default mode: after the click's button action, after a menu it
    // opened is tracked and its item's action is sent, after a drag it started.
    [self performSelector:@selector(outsideClickIsOver) withObject:nil afterDelay:0
                  inModes:@[NSDefaultRunLoopMode]];
}

- (void)outsideClickIsOver
{
    _commitScheduled = NO;
    if (self.shown)
        [self finishWithReason:TSAnnotationTextFinishOutsideClick];
}

- (BOOL)bindingIsValid
{
    PDFView *view = _boundView;
    PDFAnnotation *annotation = _boundAnnotation;
    PDFDocument *document = _boundDocument;
    if (!view || !annotation || !document)
        return NO;
    if (view.document != document)
        return NO;
    PDFPage *page = annotation.page;
    if (!page || page.document != document)
        return NO;
    return [page.annotations indexOfObjectIdenticalTo:annotation] != NSNotFound;
}

- (BOOL)changed
{
    // Alignments the segments cannot show (natural, justified) count as centered, as before.
    return ![_textView.string isEqualToString:_shownText]
        || _alignmentControl.selectedSegment != TSSegmentForAlignment(_shownAlignment);
}

- (void)finishWithReason:(TSAnnotationTextFinish)reason
{
    if (!_popover || _finished)
        return;
    _finished = YES;
    if (_commitScheduled) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(outsideClickIsOver) object:nil];
        _commitScheduled = NO;
    }
    [self stopMonitor];
    BOOL write = (reason == TSAnnotationTextFinishCommit || reason == TSAnnotationTextFinishOutsideClick)
                 && [self changed] && [self bindingIsValid];
    // The one place where the popover writes into an annotation.
    if (write) {
        PDFAnnotation *annotation = _boundAnnotation;
        annotation.contents = [_textView.string copy];
        annotation.alignment = TSAlignmentForSegment(_alignmentControl.selectedSegment);
        [_boundView setNeedsDisplay:YES];
    }
    NSPopover *popover = _popover;
    _popover = nil;
    [popover close];
    _boundView = nil;
    _boundAnnotation = nil;
    _boundDocument = nil;
}

- (void)commitBeforeSaving
{
    if (self.shown)
        [self finishWithReason:TSAnnotationTextFinishCommit];
}

- (void)discardIfBoundToView:(PDFView *)view
{
    if (self.shown && (view == nil || _boundView == view))
        [self finishWithReason:TSAnnotationTextFinishDiscard];
}

- (void)discardIfBoundToAnnotation:(PDFAnnotation *)annotation
{
    if (self.shown && _boundAnnotation == annotation)
        [self finishWithReason:TSAnnotationTextFinishDiscard];
}

- (void)ok:(id)sender
{
    [self finishWithReason:TSAnnotationTextFinishCommit];
}

- (void)alignmentChanged:(id)sender
{
    _textView.alignment = TSAlignmentForSegment(_alignmentControl.selectedSegment);
}

- (void)cancelOperation:(id)sender
{
    [self finishWithReason:TSAnnotationTextFinishCancel];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)selector
{
    if (selector == @selector(cancelOperation:)) {
        [self finishWithReason:TSAnnotationTextFinishCancel];
        return YES;
    }
    return NO;
}

// The popover can still close by itself (its window closing, for example): nothing is written then.
- (void)popoverDidClose:(NSNotification *)notification
{
    if (notification.object == _popover)
        [self finishWithReason:TSAnnotationTextFinishDiscard];
}

- (void)dealloc
{
    [self stopMonitor];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
