// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSRegexFindReplacement.h"

NS_ASSUME_NONNULL_BEGIN

/// How applying the replacements to an open document ended (spec §2.5.3a).
typedef NS_ENUM(NSInteger, TSTeXRootApplyOutcome) {
    /// Every replacement is in the text, undone at once by one Undo.
    TSTeXRootApplyOutcomeApplied,
    /// Nothing was changed: the text was not the one approved, the document refused the change at the start, or it
    /// was stopped and the text is back as it was (checked).
    TSTeXRootApplyOutcomeNotApplied,
    /// Part of the replacements is in the text: something else changed it meanwhile, or it could not be put back as it
    /// was. The text stays as it is, and the document's Undo history is gone.
    TSTeXRootApplyOutcomePartial,
} NS_SWIFT_NAME(TeXRootApplyOutcome);

typedef NS_ENUM(NSInteger, TSTeXRootApplyReason) {
    TSTeXRootApplyReasonNone,
    /// The text is not the one approved (edited, closed, or the view is another one).
    TSTeXRootApplyReasonChanged,
    /// The document did not accept the change (shouldChangeTextInRanges:).
    TSTeXRootApplyReasonRefused,
    TSTeXRootApplyReasonStopped,
    /// The text was changed meanwhile by something else than the replacements.
    TSTeXRootApplyReasonUnexpectedChange,
} NS_SWIFT_NAME(TeXRootApplyReason);

/// Puts the replacements of one open document in its text on the main thread, a part at a time so that no part keeps
/// the main thread longer than about 100 ms (spec §2.9): at most `maximumReplacements` replacements and
/// `maximumCharacters` characters inserted per part, a long inserted string being split into several inserts. Events
/// are handled between the parts, from the end of the text to its start. The text views stay read-only between the
/// parts; each part makes the view editable only while it changes the text, through the text view
/// (shouldChangeTextInRanges:, didChangeText).
///
/// Undo: the parts register nothing; once all are in, one action is registered that takes them all back at once
/// through the text view (which registers the Redo), so that one Undo takes back the whole Replace All of the
/// document, as after Replace All in the Advanced Find panel. Stop (or a part refused) takes back the parts applied, a
/// part at a time too, and checks the text is then the one approved. Any other change of the text meanwhile ends it as
/// partial: the text stays as it is and the document's Undo history goes, as it no longer fits the text (spec
/// §2.5.3a). Meanwhile Undo and Redo must not reach the document (TSTeXRootReplaceGuard).
NS_SWIFT_NAME(TeXRootDocumentApplier)
@interface TSTeXRootDocumentApplier : NSObject
/// `replacements` ascending, not overlapping, in `originalText`, which is the text approved.
- (instancetype)initWithTextView:(NSTextView *)textView replacements:(NSArray<TSRegexFindReplacement *> *)replacements
                    originalText:(NSString *)originalText actionName:(NSString *)actionName NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic) NSUInteger maximumReplacements;
@property (nonatomic) NSUInteger maximumCharacters;
@property (nonatomic, readonly, weak) NSTextView *textView;
@property (nonatomic, readonly, copy) NSString *originalText;
/// From the first part until it ended (the guard of spec §2.5.3a).
@property (nonatomic, readonly, getter=isApplying) BOOL applying;
@property (nonatomic, readonly) TSTeXRootApplyOutcome outcome;
@property (nonatomic, readonly) TSTeXRootApplyReason reason;
/// The parts applied so far.
@property (nonatomic, readonly) NSUInteger numberOfParts;

/// Checks the text is the one approved and starts; `completion` is called once, on the main thread.
- (void)startWithCompletion:(void (^)(TSTeXRootDocumentApplier *applier))completion;
/// Ends after the part being applied: the parts applied are taken back (spec §2.5.3a).
- (void)stop;

/// For the tests: called between two parts.
@property (nonatomic, copy, nullable) void (^betweenParts)(TSTeXRootDocumentApplier *applier);
/// For the tests: the change of a part is refused from this part on (0: never).
@property (nonatomic) NSUInteger refusesFromPart;
@end

/// What is being replaced now, for TSDocument and the application (spec §2.5.1a, §2.5.3a).
NS_SWIFT_NAME(TeXRootReplaceGuard)
@interface TSTeXRootReplaceGuard : NSObject
/// From the approval of a Replace All until its report.
@property (class, nonatomic, readonly, getter=isRunning) BOOL running;
/// A document's text is being replaced in parts: saving, closing, reverting, typesetting and changes by AppleScript
/// are refused; a reload of the file is put off.
+ (BOOL)isApplyingToTextStorage:(nullable NSTextStorage *)storage;
/// Undo and Redo are refused for the text (from the approval of a Replace All that replaces in it until its report).
+ (BOOL)locksTextStorage:(nullable NSTextStorage *)storage;
+ (void)setLockedTextStorages:(nullable NSArray<NSTextStorage *> *)storages;
+ (BOOL)isApplying;
/// Called once nothing is being applied any more (at once when nothing is).
+ (void)performWhenNotApplying:(dispatch_block_t)block;
+ (void)setRunning:(BOOL)running;
+ (void)addApplier:(TSTeXRootDocumentApplier *)applier;
+ (void)removeApplier:(TSTeXRootDocumentApplier *)applier;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
