// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSDocument-AnnotationBar.m
 *
 * The annotation toolbar of a document (Issue #49). The document is the bar's host: it
 * keeps edit mode for both parts of its Preview, chooses the part the tools act on, and
 * shows the bar under the toolbar of the window that shows its Preview.
 */

#import "TSDocument.h"
#import "MyPDFKitView.h"
#import "TSAnnotationBar.h"
#import "TSAnnotationTextPopover.h"
#import "TSDocumentWindowGlass.h"
#import "TSPreviewPanePlace.h"

@implementation TSDocument (AnnotationBar)

#pragma mark Host

- (TSAnnotationBar *)annotationBar
{
    return _annotationBar;
}

- (BOOL)annotationEditMode
{
    return _annotationEditMode;
}

- (BOOL)annotationSaveAllPages
{
    return _annotationSaveAllPages;
}

- (void)setAnnotationSaveAllPages:(BOOL)all
{
    _annotationSaveAllPages = all;
}

// The window that shows the Preview: the Preview window, or the window that shows both.
- (NSWindow *)annotationBarWindow
{
    return [self useFullSplitWindow] ? [self fullSplitWindow] : self.pdfKitWindow;
}

- (PDFView *)annotationTargetView
{
    TSPreviewWindow *window = self.pdfKitWindow;
    PDFView *active = window.activeView;
    if (active != nil && active == self.myPDFKitView)
        return active;
    if (active != nil && active == self.myPDFKitView2 && window.windowIsSplit)
        return active;
    return self.myPDFKitView;
}

- (BOOL)annotationViewBelongsToHost:(NSResponder *)responder
{
    if (![responder isKindOfClass:NSView.class])
        return NO;
    NSView *view = (NSView *)responder;
    PDFView *first = self.myPDFKitView, *second = self.myPDFKitView2;
    return (first != nil && (view == first || [view isDescendantOf:first])) ||
           (second != nil && (view == second || [view isDescendantOf:second]));
}

- (void)performAnnotationCommand:(SEL)command
{
    PDFView *view = [self annotationTargetView];
    if (view == nil)
        return;
    NSWindow *window = view.window;
    if (window != nil) {
        if (!window.isKeyWindow)
            [window makeKeyAndOrderFront:nil];
        if (window.firstResponder != view)
            [window makeFirstResponder:view];
    }
    [NSApp sendAction:command to:view from:_annotationBar];
}

// The one way into and out of edit mode (Issue #49 spec §3.4.1).
- (void)setAnnotationEditMode:(BOOL)on
{
    if (_annotationEditMode == on) {
        [_annotationBar updateControls];
        return;
    }
    _annotationEditMode = on;
    if (on) {
        self.annotationsExist = YES;
        // Edit mode is shown and left with the bar.
        if (_annotationBar.attachedWindow == nil)
            [self showAnnotationBar];
    } else {
        [_annotationBar.textPopover finishWithReason:TSAnnotationTextFinishDiscard];
        [_annotationBar closeSharedPanelsIfOwned];
    }
    [(MyPDFKitView *)self.myPDFKitView applyAnnotationEditMode:on];
    [(MyPDFKitView *)self.myPDFKitView2 applyAnnotationEditMode:on];
    self.docUseAnnotationMenu = on;
    [_annotationBar updateControls];
}

#pragma mark Showing the bar

- (void)showAnnotationBar
{
    if (_annotationBar == nil)
        _annotationBar = [[TSAnnotationBar alloc] initWithHost:self];
    NSWindow *window = [self annotationBarWindow];
    if (window == nil || _annotationBar.attachedWindow == window)
        return;
    TSAnnotationBar *bar = _annotationBar;
    [self keepPreviewPlaceInWindow:window while:^{
        [bar attachToWindow:window];
    }];
}

- (void)hideAnnotationBar
{
    TSAnnotationBar *bar = _annotationBar;
    NSWindow *window = bar.attachedWindow;
    if (window == nil)
        return;
    [self setAnnotationEditMode:NO];
    [bar.textPopover finishWithReason:TSAnnotationTextFinishDiscard];
    [bar closeSharedPanelsIfOwned];
    // annotationsExist stays: the guard rails still ask to save before typesetting or closing.
    [self keepPreviewPlaceInWindow:window while:^{
        [bar detach];
    }];
}

- (IBAction)displayChoicesPanel:(id)sender
{
    if (_annotationBar.attachedWindow != nil)
        [self hideAnnotationBar];
    else
        [self showAnnotationBar];
}

- (BOOL)validateAnnotationBarItem:(NSMenuItem *)item
{
    BOOL shown = _annotationBar.attachedWindow != nil;
    item.title = shown ? NSLocalizedString(@"Hide Annotation Toolbar", @"Preview menu")
                       : NSLocalizedString(@"Show Annotation Toolbar", @"Preview menu");
    // Only from the window that shows the Preview: the document also answers in the source window.
    NSWindow *window = [self annotationBarWindow];
    return window != nil && (window == NSApp.mainWindow || window == NSApp.keyWindow);
}

- (IBAction)editAnnotationText:(id)sender
{
    if (_annotationBar.attachedWindow == nil)
        return;
    [_annotationBar editText:sender];
}

#pragma mark Following the windows

- (void)annotationBarFollowWindowChange
{
    TSAnnotationBar *bar = _annotationBar;
    NSWindow *old = bar.attachedWindow;
    if (old == nil)
        return;
    NSWindow *window = [self annotationBarWindow];
    if (window == old)
        return;
    [bar.textPopover finishWithReason:TSAnnotationTextFinishDiscard];
    [bar detach];
    [self keepPreviewPlaceInWindow:window while:^{
        [bar attachToWindow:window];
    }];
}

- (void)annotationWindowWillClose:(NSWindow *)window
{
    NSWindow *attached = _annotationBar.attachedWindow;
    if (attached == nil || (window != nil && window != attached))
        return;
    [_annotationBar.textPopover finishWithReason:TSAnnotationTextFinishDiscard];
    [self setAnnotationEditMode:NO];
    [_annotationBar closeSharedPanelsIfOwned];
    [_annotationBar detach];
}

- (void)annotationPartWillCollapse:(PDFView *)view
{
    [_annotationBar.textPopover discardIfBoundToView:view];
}

- (void)annotationsWillBeSaved
{
    [_annotationBar.textPopover commitBeforeSaving];
}

- (void)annotationWillBeRemoved:(PDFAnnotation *)annotation
{
    [_annotationBar.textPopover discardIfBoundToAnnotation:annotation];
}

// A part of the Preview got another PDF, as after typesetting: the text being edited is dropped.
- (void)annotationViewDocumentChanged:(NSNotification *)notification
{
    id view = notification.object;
    if ([view isKindOfClass:PDFView.class] && [self annotationViewBelongsToHost:view])
        [_annotationBar.textPopover discardIfBoundToView:(PDFView *)view];
}

#pragma mark Keeping the Preview in place (spec §3.8)

// The bar changes the height of what can be seen of the Preview. Each part keeps the text
// at the top of what can be seen, a split into a top and a bottom part keeps the shares of
// what can be seen, and an open drawer starts below the toolbar and the bar again.
- (void)keepPreviewPlaceInWindow:(NSWindow *)window while:(void (NS_NOESCAPE ^)(void))change
{
    TSPreviewWindow *preview = self.pdfKitWindow;
    NSSplitView *split = preview.pdfKitSplitView;
    MyPDFKitView *first = (MyPDFKitView *)self.myPDFKitView;
    MyPDFKitView *second = (MyPDFKitView *)self.myPDFKitView2;
    BOOL splitShown = preview.windowIsSplit && split.window == window && split.arrangedSubviews.count >= 2;
    BOOL keepShares = splitShown && !split.isVertical;
    CGFloat firstShare = 0, secondShare = 0;
    if (keepShares) {
        CGFloat hidden = TSDocumentWindowHiddenTop(split);
        firstShare = MAX(0, NSHeight(split.arrangedSubviews[0].frame) - hidden);
        secondShare = NSHeight(split.arrangedSubviews[1].frame);
    }
    BOOL keepFirst = first.window == window && first.document != nil;
    BOOL keepSecond = splitShown && second.document != nil;
    TSPreviewPanePlace firstPlace = keepFirst ? TSPreviewPaneCapture(first) : (TSPreviewPanePlace){0};
    TSPreviewPanePlace secondPlace = keepSecond ? TSPreviewPaneCapture(second) : (TSPreviewPanePlace){0};

    change();

    [window layoutIfNeeded];
    [window.contentView layoutSubtreeIfNeeded];
    if (keepShares && firstShare + secondShare > 0)
        TSDocumentWindowSplitInShares(split, firstShare, secondShare);
    TSDocumentWindowPlaceDrawers(window);
    if (keepFirst)
        TSPreviewPaneRestore(first, firstPlace);
    if (keepSecond)
        TSPreviewPaneRestore(second, secondPlace);
    // PDFKit may lay the pages out again once the window has settled.
    __weak MyPDFKitView *weakFirst = first, *weakSecond = second;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (keepFirst && weakFirst)
            TSPreviewPaneRestore(weakFirst, firstPlace);
        if (keepSecond && weakSecond)
            TSPreviewPaneRestore(weakSecond, secondPlace);
    });
}

@end
