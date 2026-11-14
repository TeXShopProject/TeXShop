// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindResults.h"
#import "TSAdvancedFindSettings.h"

NS_ASSUME_NONNULL_BEGIN

/// The list of the matches of a "Find All", shown in the panel under the options, as CotEditor does: a header with a
/// button that closes the list, the count and the find string, then the line and the matched text of each match.
/// A click on a row (or the arrow keys) jumps to the match: it is selected, scrolled to and flashed in the document;
/// a double click also brings the document to the front. The list follows the edits (TSAdvancedFindResults).
NS_SWIFT_NAME(AdvancedFindResultsView)
@interface TSAdvancedFindResultsView : NSView <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithSettings:(TSAdvancedFindSettings *)settings NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Lists `results`, found in `textView`, in place of the last list.
- (void)setResults:(TSAdvancedFindResults *)results textView:(NSTextView *)textView;
/// Drops the list: it no longer follows the text.
- (void)clear;

@property (nonatomic, readonly, nullable) TSAdvancedFindResults *results;
@property (nonatomic, readonly, weak) NSTextView *textView;
@property (nonatomic, readonly) NSTableView *tableView;
@property (nonatomic, readonly) NSTextField *countField;
@property (nonatomic, readonly) NSButton *liveUpdateBox;
@property (nonatomic, readonly) NSButton *closeButton;
/// Called by the close button and when the document window of the list closes.
@property (nonatomic, copy, nullable) void (^closeHandler)(void);
/// NSBeep unless replaced (tests stay silent).
@property (nonatomic, copy) void (^beepHandler)(void);
/// The height the list needs to show its header and a few rows.
@property (nonatomic, readonly) CGFloat minimumHeight;
/// The colors of the groups (by number, round) in the list; the match has the highlight color.
@property (class, nonatomic, readonly) NSArray<NSColor *> *groupColors;

/// Selects the match of the row in the document, also a stale one; NO (and a beep) when its document is gone.
- (BOOL)showItemAtRow:(NSInteger)row;

@end

NS_ASSUME_NONNULL_END
