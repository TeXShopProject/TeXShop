// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// One change of the text: the characters in `range` (before the change) were replaced by `replacementLength` new ones.
NS_SWIFT_NAME(AdvancedFindTextEdit)
@interface TSAdvancedFindTextEdit : NSObject
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly) NSUInteger replacementLength;
- (instancetype)initWithRange:(NSRange)range replacementLength:(NSUInteger)replacementLength NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// A long search or replacement: Replace All, Find All, Multiple Replace. The work runs on a copy of the text on a
/// background queue; meanwhile every text view of the document is read-only, and the result is applied on the main
/// thread, in one step, after they are editable again. When the work takes longer than `sheetDelay`, a sheet with its
/// progress and a Cancel button comes down from the document window.
NS_SWIFT_NAME(AdvancedFindTask)
@interface TSAdvancedFindTask : NSObject

- (instancetype)initWithTitle:(NSString *)title textView:(NSTextView *)textView NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The action's name, the title of the sheet ("Replace All").
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, weak) NSTextView *textView;
/// From 0 to 1, or below 0 when the work cannot tell (the sheet's bar then moves on its own). Set from the work.
@property (atomic) double progress;
/// A short line under the bar ("Searching… 1,204"). Set from the work.
@property (atomic, copy) NSString *message;
/// Seconds before the sheet comes down; 0.4 unless changed. A task that ends sooner never shows it.
@property (nonatomic) NSTimeInterval sheetDelay;
/// The delay passed while the work was running: the sheet was due (shown when the document window is on screen).
@property (nonatomic, readonly) BOOL sheetWasDue;
@property (nonatomic, readonly, nullable) NSWindow *sheet;
@property (atomic, readonly, getter=isCancelled) BOOL cancelled;
@property (nonatomic, readonly, getter=isFinished) BOOL finished;

/// For the engine's `isCancelled` parameters; safe to call from the work's queue.
@property (nonatomic, readonly) BOOL (^cancellation)(void);

- (void)cancel;

/// The changes of the text while the work ran, in order. Only a text that is read-only anyway changes meanwhile: the
/// console and the log, which go on receiving the output of a typesetting.
@property (nonatomic, readonly, copy) NSArray<TSAdvancedFindTextEdit *> *editsMeanwhile;

/// Makes the document's text views read-only, runs `work` on a background queue, then, on the main thread, makes them
/// editable again and calls `completion` with the work's result (nil when cancelled).
- (void)runWork:(id _Nullable (^)(TSAdvancedFindTask *task))work completion:(void (^)(id _Nullable result, BOOL cancelled))completion;

@end

NS_ASSUME_NONNULL_END
