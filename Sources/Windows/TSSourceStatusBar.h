// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSSourceStatusBar.h
 *
 * The status bar under the source of a document, in the source window and in the source
 * side of the window that shows both. From the left it shows the lines, characters and words
 * of the whole text, each followed by the number in the selection in parentheses when the
 * selection holds some, then the location, line and column of the insertion point; at the
 * right it shows the size of the saved file. The numbers follow the text view being typed in.
 *
 * Source > Show Status Bar shows or hides the bars of all documents at once; the choice is kept
 * in the defaults (ShowStatusBar, on by default). The numbers are counted on a background queue,
 * a short moment after the text or the selection stops changing (longer for a long text), so
 * typing in a large document does not wait for them.
 */

#import <Cocoa/Cocoa.h>
#import "TSStatusBarCounting.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted when the status bars are shown or hidden.
extern NSNotificationName const TSSourceStatusBarShownDidChangeNotification;

@interface TSSourceStatusBar : NSView

/// Whether the status bars are shown (the ShowStatusBar default).
@property (class, nonatomic) BOOL shown;
/// The height of the bar: taller on macOS 26 and later, whose windows have larger corners.
@property (class, nonatomic, readonly) CGFloat barHeight;

/// A bar for the text of `textStorage`, shown in `textViews` (the parts of the source). `activeTextView` gives the part
/// being typed in; the selection and the insertion point are taken from it.
- (instancetype)initWithTextStorage:(NSTextStorage *)textStorage textViews:(NSArray<NSTextView *> *)textViews
                     activeTextView:(NSTextView *_Nullable (^)(void))activeTextView NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Puts the bar at the bottom of the superview of `sourceView` and `sourceView` above it, or, while the bars are
/// hidden, takes the bar away and gives `sourceView` the whole superview. Called again whenever `sourceView` moves
/// to another window.
- (void)placeBelowView:(NSView *)sourceView;
/// The text view being typed in changed, or its selection changed in a way the text views do not announce.
- (void)selectionDidChange;
/// The document was read or saved: the size of the file at `fileURL` is read again. nil for a document never saved.
- (void)fileDidChangeAtURL:(nullable NSURL *)fileURL;
/// Stops counting and watching; the document is closing.
- (void)stop;

/// The numbers shown, NSNotFound for those not counted yet.
@property (nonatomic, readonly) TSStatusBarCounts counts;
/// The size of the file, or nil when the document has no saved file.
@property (nonatomic, readonly, nullable) NSNumber *fileSize;
/// The items as they are drawn now, in order, and the file size text (nil when not shown). For the tests.
@property (nonatomic, readonly) NSArray<NSString *> *visibleItems;
@property (nonatomic, readonly, nullable) NSString *visibleFileSize;
/// The text of every item, whether or not it fits.
@property (nonatomic, readonly) NSArray<NSString *> *allItems;
/// Counts now, on the calling thread, instead of waiting for the background queue. For the tests.
- (void)countNow;
/// YES while a count is waiting or running.
@property (nonatomic, readonly, getter=isCounting) BOOL counting;

@end

NS_ASSUME_NONNULL_END
