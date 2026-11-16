// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSAnnotationTextPopover.h
 *
 * Edits the text of a text annotation (FreeText) in a popover from the annotation
 * toolbar. The popover is bound to the annotation it was opened for, so its text
 * goes there or nowhere. When it closes is decided in one place (Issue #49 spec §3.6.3):
 * - something that makes the binding useless discards at once;
 * - a click outside the popover commits only after what the click started is over,
 *   so a click that hides the bar or ends the split discards first;
 * - saving the annotations commits first, because the save panel runs modally.
 */

#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSAnnotationTextFinish) {
    TSAnnotationTextFinishCommit,        // OK, Command-Return, the text button, or before saving
    TSAnnotationTextFinishCancel,        // Escape
    TSAnnotationTextFinishDiscard,       // the binding is no longer useful
    TSAnnotationTextFinishOutsideClick,  // a click outside, once what it started is over
};

@interface TSAnnotationTextPopover : NSViewController

/// YES for the annotations whose text the popover edits: text, and text with a background.
+ (BOOL)canEditAnnotation:(nullable PDFAnnotation *)annotation;

@property (nonatomic, readonly) BOOL shown;
@property (nonatomic, weak, readonly, nullable) PDFView *boundView;
@property (nonatomic, weak, readonly, nullable) PDFAnnotation *boundAnnotation;

/// Opens the popover under a control for the annotation selected in a view.
- (void)showForAnnotation:(PDFAnnotation *)annotation inView:(PDFView *)view relativeToView:(NSView *)anchor;
/// Closes the popover for a reason; only the first reason after it opened counts.
- (void)finishWithReason:(TSAnnotationTextFinish)reason;

/// Saving is about to start: what is shown goes into the annotation first.
- (void)commitBeforeSaving;
/// The view's PDF was replaced, or the view stops being a part of the Preview.
- (void)discardIfBoundToView:(PDFView *)view;
/// The annotation is about to be removed from its page.
- (void)discardIfBoundToAnnotation:(PDFAnnotation *)annotation;

// For tests.
@property (nonatomic, readonly) NSTextView *textView;
@property (nonatomic, readonly) NSSegmentedControl *alignmentControl;
@property (nonatomic, readonly) NSButton *okButton;
/// What the event monitor does with a click outside the popover: schedule the commit.
- (void)noteOutsideClick;
/// The scheduled commit, run once what the click started is over.
- (void)outsideClickIsOver;

@end

NS_ASSUME_NONNULL_END
