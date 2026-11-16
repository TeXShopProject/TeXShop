// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSTeXRootSearchModel.h"

NS_ASSUME_NONNULL_BEGIN

/// The tree of the files collected (spec §2.3): the root's folder on top, the folders that hold files, and the
/// files, the root first. Each row has a check box with three states (a folder turns all below it on or off), the
/// name, the number of items, and ⊘ in the replacing modes for a file that cannot be replaced in (its tool tip says
/// why).
NS_SWIFT_NAME(TeXRootSearchFileTree)
@interface TSTeXRootSearchFileTree : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)initWithModel:(TSTeXRootSearchModel *)model NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) NSScrollView *scrollView;
@property (nonatomic, readonly) NSOutlineView *outlineView;

/// Builds the tree again when the project changed; otherwise shows the checks, counts and marks as they are now.
- (void)reload;

/// For the tests: the state of a file's or folder's check box, the files under a row, and a row's spoken label.
- (NSControlStateValue)stateOfRow:(NSInteger)row;
- (NSArray<TSTeXRootProjectFile *> *)filesOfRow:(NSInteger)row;
/// As if the check box of the row was clicked.
- (void)toggleRow:(NSInteger)row;
- (NSString *)accessibilityLabelOfRow:(NSInteger)row;

@end

NS_ASSUME_NONNULL_END
