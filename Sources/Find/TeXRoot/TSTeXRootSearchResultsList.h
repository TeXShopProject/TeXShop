// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSTeXRootSearchModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The words for why a file cannot be replaced in (the ⊘ mark's tool tip and its VoiceOver description).
FOUNDATION_EXPORT NSString *TSTeXRootSearchOnlyReasonText(TSTeXRootSearchOnlyReason reason);

/// The list of the results (spec §2.4): a heading for each file (its path below the root's folder and how many
/// items), and under it one row per item: a check box in the replacing modes (⊘ in a file that cannot be replaced
/// in), the line number, the lines as they are with the match marked, and in the replacing modes the lines after
/// the replacement with what was put in marked. An empty match is a thin mark at its place.
NS_SWIFT_NAME(TeXRootSearchResultsList)
@interface TSTeXRootSearchResultsList : NSObject <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)initWithModel:(TSTeXRootSearchModel *)model NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) NSScrollView *scrollView;
/// A flat table: a heading row per file (a group row), then its items. Nothing is made per item when the results
/// change, so that even 500,000 items are listed at once (spec §2.9).
@property (nonatomic, readonly) NSTableView *tableView;
/// The font of the lines: the source font, at most 14 points.
@property (nonatomic, strong) NSFont *font;
/// A row was clicked (`front` NO) or double-clicked (`front` YES), or Return was pressed on it.
@property (nonatomic, copy, nullable) void (^showItemHandler)(TSTeXRootSearchFileResult *file, TSTeXRootSearchItem *item, BOOL front);

/// Shows the model's results as they are now, keeping the scroll position when the files are the same.
- (void)reload;

/// The row of a file's heading or of an item, -1 when it is not listed; the file or item of a row.
- (NSInteger)rowOfObject:(id)object;
- (nullable id)objectAtRow:(NSInteger)row;

/// For the tests: the rows as VoiceOver reads them, and the texts shown in an item's row.
- (NSString *)accessibilityLabelOfRow:(NSInteger)row;
- (nullable NSAttributedString *)shownTextOfItem:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file after:(BOOL)after;

@end

NS_ASSUME_NONNULL_END
