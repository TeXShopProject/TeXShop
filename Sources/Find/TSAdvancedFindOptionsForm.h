// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSRegexFindOptions.h"
#import "TSRegexReplacementTemplate.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSAdvancedFindOptionsFormStyle) {
    /// The panel searches either way at a time, so the other section cannot be changed (as in CotEditor).
    TSAdvancedFindOptionsFormStylePanel,
    /// A multiple replacement set: each rule chooses, so both sections can be changed.
    TSAdvancedFindOptionsFormStyleSet,
} NS_SWIFT_NAME(AdvancedFindOptionsFormStyle);

/// The options shown in the panel's "More Options" and in a multiple replacement set, in one layout:
/// text search, regular expression (with the replacement syntax), and both.
NS_SWIFT_NAME(AdvancedFindOptionsForm)
@interface TSAdvancedFindOptionsForm : NSObject

/// The bits of the text search section.
@property (class, nonatomic, readonly) TSRegexFindOptions textualItemOptions;

@property (nonatomic, readonly) TSAdvancedFindOptionsFormStyle style;
@property (nonatomic, readonly) NSStackView *view;
@property (nonatomic, readonly) TSRegexFindOptions textualOptions;
@property (nonatomic, readonly) TSRegexFindOptions regularExpressionOptions;
@property (nonatomic, readonly) TSRegexReplacementSyntax replacementSyntax;
/// Panel style: which section can be changed. Ignored for a set.
@property (nonatomic) BOOL usesRegularExpression;
@property (nonatomic, copy, nullable) void (^changeHandler)(TSAdvancedFindOptionsForm *form);

- (instancetype)initWithStyle:(TSAdvancedFindOptionsFormStyle)style
               textualOptions:(TSRegexFindOptions)textualOptions
     regularExpressionOptions:(TSRegexFindOptions)regularExpressionOptions
            replacementSyntax:(TSRegexReplacementSyntax)replacementSyntax NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Adds a section of the owner's own at the end. Check boxes in `rows` are made small, as the form's.
- (void)addSectionTitle:(NSString *)title rows:(NSArray<NSView *> *)rows;
/// Puts a title over the form (centered, as CotEditor's options) and rows without a section title under it
/// (the panel's "wrap around" and so on).
- (void)insertTitle:(NSString *)title rows:(NSArray<NSView *> *)rows;

@end

NS_ASSUME_NONNULL_END
