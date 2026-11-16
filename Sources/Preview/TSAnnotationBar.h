// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSAnnotationBar.h
 *
 * The annotation toolbar: a band under the toolbar of the Preview window, or of the
 * window that shows the source and the Preview, holding the tools that annotate the
 * PDF of that window's document. It replaces the floating Annotation Panel, so every
 * window shows its own tools and they act on its own document only.
 */

#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAnnotationTextPopover;

/// The document whose window shows the bar.
@protocol TSAnnotationBarHost <NSObject>
/// Edit mode of the document's Preview: both parts of a split Preview are in it or out of it.
@property (nonatomic, readonly) BOOL annotationEditMode;
- (void)setAnnotationEditMode:(BOOL)on;
/// The part of the Preview the tools act on: the active part, or the first part.
- (nullable PDFView *)annotationTargetView;
/// YES for the views of the document's Preview (both parts).
- (BOOL)annotationViewBelongsToHost:(nullable NSResponder *)responder;
/// Sends a tool's action to the target view, which becomes the first responder of its window.
- (void)performAnnotationCommand:(SEL)command;
/// Hides the bar (its close button and the Preview menu item).
- (void)hideAnnotationBar;
/// Whether Save Annotations saves every page, or only the annotated pages.
@property (nonatomic) BOOL annotationSaveAllPages;
@end

@interface TSAnnotationBar : NSTitlebarAccessoryViewController

- (instancetype)initWithHost:(id<TSAnnotationBarHost>)host NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, weak, readonly) id<TSAnnotationBarHost> host;
/// The window the bar is attached to, or nil.
@property (nonatomic, weak, readonly, nullable) NSWindow *attachedWindow;
@property (nonatomic, readonly) TSAnnotationTextPopover *textPopover;

/// Puts the bar under the toolbar of a window, moving it from any window it was in.
/// While the bar is shown, the window is at least as wide as the narrowest bar.
- (void)attachToWindow:(NSWindow *)window;
/// Takes the bar off its window and gives the window back its minimum size.
- (void)detach;

/// Brings the controls up to date with the host: edit mode, the selected annotation, Save All.
- (void)updateControls;

/// Closes the shared color and font panels if this bar opened them and they still serve this
/// document (see the Issue #49 spec, §3.7). Called when the bar closes or edit mode ends.
- (void)closeSharedPanelsIfOwned;

/// The text button: opens the text popover for the selected text annotation, or commits
/// and closes it when it is open.
- (IBAction)editText:(nullable id)sender;

// For tests: the two layouts and the controls.
@property (nonatomic, readonly) BOOL compact;
@property (nonatomic, readonly) CGFloat fullWidth;
@property (nonatomic, readonly) CGFloat compactWidth;
@property (nonatomic, readonly) NSButton *editModeButton;
@property (nonatomic, readonly) NSArray<NSButton *> *toolButtons;
@property (nonatomic, readonly) NSButton *colorButton;
@property (nonatomic, readonly) NSButton *fontButton;
@property (nonatomic, readonly) NSButton *textButton;
@property (nonatomic, readonly) NSPopUpButton *moreButton;
@property (nonatomic, readonly) NSButton *saveButton;
@property (nonatomic, readonly) NSButton *saveAllCheckBox;
@property (nonatomic, readonly) NSPopUpButton *overflowButton;
@property (nonatomic, readonly) NSButton *closeButton;
@property (nonatomic, readonly) BOOL ownsColorPanel;
@property (nonatomic, readonly) BOOL ownsFontPanel;
/// Lays the bar out for a width, as when its window is resized.
- (void)layoutForWidth:(CGFloat)width;

@end

/// The tools of the bar in order: the action each one sends to the Preview, and its name.
typedef struct {
    SEL action;
    __unsafe_unretained NSString *name;
} TSAnnotationTool;
FOUNDATION_EXPORT NSUInteger TSAnnotationToolCount(void);
FOUNDATION_EXPORT TSAnnotationTool TSAnnotationToolAtIndex(NSUInteger index);

NS_ASSUME_NONNULL_END
