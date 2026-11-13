// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSRegexMultipleReplace.h"

NS_ASSUME_NONNULL_BEGIN

/// Why each enabled rule of a set cannot be used (an empty or invalid find string), keyed by the rule's index.
/// The engine skips these rules; the table marks them before anything is applied.
FOUNDATION_EXPORT NSDictionary<NSNumber *, NSError *> *TSMultipleReplaceProblems(TSRegexMultipleReplace *set);

/// The find or the replacement column of a rule.
typedef NS_ENUM(NSInteger, TSMultipleReplaceRuleField) {
    TSMultipleReplaceRuleFieldFind,
    TSMultipleReplaceRuleFieldReplace,
} NS_SWIFT_NAME(MultipleReplaceRuleField);

/// The table of rules of one set: editing, adding, removing and reordering by dragging.
/// Every change makes a new set and calls `setChangedHandler`.
NS_SWIFT_NAME(MultipleReplaceRuleTable)
@interface TSMultipleReplaceRuleTable : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

@property (nonatomic, readonly) NSTableView *tableView;
@property (nonatomic, strong, nullable) TSRegexMultipleReplace *set;
/// The matches replaced by each rule in the last application; nil until then. Cleared when the set changes.
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *counts;
@property (nonatomic, copy, nullable) void (^setChangedHandler)(TSRegexMultipleReplace *set);
/// Colors the text of a find or replacement cell (the rule, its column, its pattern options and the plain
/// attributes are given); nil, or a nil result, shows it plain.
@property (nonatomic, copy, nullable) NSAttributedString *_Nullable (^fieldStyler)(NSString *string, TSRegexReplacementRule *rule,
    TSMultipleReplaceRuleField field, TSRegexFindOptions options, NSDictionary<NSAttributedStringKey, id> *attributes);

/// Makes the table and its columns.
- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)addRule;
- (void)removeSelectedRules;
/// Moves the rules to the row (indexes of the rows before the move), as a drop does.
- (void)moveRulesAtIndexes:(NSIndexSet *)indexes toRow:(NSInteger)row;
/// Replaces one rule (editing in the table does this).
- (void)replaceRuleAtIndex:(NSUInteger)index withRule:(TSRegexReplacementRule *)rule;

@end

NS_ASSUME_NONNULL_END
