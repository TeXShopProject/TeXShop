// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSTextStatisticsPopover.h
 *
 * Text Statistics, a popover opened from the status bar under the source (or from Edit >
 * Statistics…). It shows the characters, words and lines of the whole document, or of the
 * selection, in two columns: Source, counted as the status bar counts, and Text, what detex
 * leaves of it without the TeX commands, with the files of \input and \include. detex runs
 * only when the popover opens and when its refresh button is pressed, never while typing;
 * the time of the count shows how old the numbers are.
 */

#import <Cocoa/Cocoa.h>
#import "TSTextStatistics.h"

NS_ASSUME_NONNULL_BEGIN

/// The content of the popover.
@interface TSTextStatisticsViewController : NSViewController
/// Called by the refresh button.
@property (nonatomic, copy, nullable) void (^refresh)(void);
/// A count runs: a spinner in place of the table.
- (void)showCountingSelection:(BOOL)selection;
- (void)showResult:(TSTextStatisticsResult *)result;

/// What is shown, for the tests: the heading, the time, and the cells of the table by row (Characters, Words, Lines)
/// as "name|source|text"; nil cells are empty; the warning in place of the Text column, or nil.
@property (nonatomic, readonly) NSString *heading;
@property (nonatomic, readonly) NSString *time;
@property (nonatomic, readonly) NSArray<NSString *> *rows;
@property (nonatomic, readonly, nullable) NSString *warning;
@property (nonatomic, readonly, getter=isCounting) BOOL counting;
/// The ⓘ beside the Text heading.
@property (nonatomic, readonly) NSView *infoMark;
@property (nonatomic, readonly) NSButton *refreshButton;
@end

/// The popover of one document.
@interface TSTextStatisticsPopover : NSObject <NSPopoverDelegate>
/// `source` gives the text and the ranges to count, the folder for \input and \include (nil for a document never saved)
/// and the document's encoding, each time a count starts.
- (instancetype)initWithSource:(void (^)(NSString *_Nullable *_Nonnull text, NSArray<NSValue *> *_Nullable *_Nonnull ranges,
                                         NSURL *_Nullable *_Nonnull folder, NSStringEncoding *_Nonnull encoding))source NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Opens the popover pointing at `rect` of `view` and counts. When it is open already, it counts again.
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge;
- (void)close;
/// The refresh button: counts again.
- (void)refresh;

@property (nonatomic, readonly) NSPopover *popover;
@property (nonatomic, readonly) TSTextStatisticsViewController *contentController;
@property (nonatomic, readonly) TSTextStatistics *statistics;
/// The detex used; by default the one in the TeX bin folder of the settings (TetexBinPath).
@property (nonatomic, copy, nullable) NSURL *_Nullable (^detex)(void);
/// How many counts started, for the tests.
@property (nonatomic, readonly) NSUInteger countsStarted;

@end

NS_ASSUME_NONNULL_END
