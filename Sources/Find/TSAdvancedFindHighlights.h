// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Adopted by a layout manager that already draws the search highlights after super's background (TSLayoutManager).
NS_SWIFT_NAME(AdvancedFindHighlightDrawing)
@protocol TSAdvancedFindHighlightDrawing <NSObject>
@end

/// The search highlights of one text storage. They are not temporary attributes: the ranges are kept here
/// and drawn by the layout manager over the background that is already there, so nothing underneath is overwritten
/// or lost when they are removed. Every view of the storage (a split window) shows them.
NS_SWIFT_NAME(AdvancedFindHighlights)
@interface TSAdvancedFindHighlights : NSObject

/// The highlights of `storage`, made on first use.
+ (instancetype)highlightsForTextStorage:(NSTextStorage *)storage;
+ (nullable instancetype)existingHighlightsForTextStorage:(NSTextStorage *)storage;

@property (nonatomic, readonly, weak) NSTextStorage *textStorage;
/// The matches, sorted by their start: those of one search do not overlap, those of Multiple Replace may contain each
/// other. Edits move the ranges after them and drop the ones they touch. Setting them removes the groups.
@property (nonatomic, copy) NSArray<NSValue *> *ranges;
/// The groups of each match, in the order of `ranges` (element k - 1 is group k, {NSNotFound, 0} if it did not take
/// part), or empty when the matches have no groups; made on request. A match goes with its groups: an edit that touches
/// the match or one of its groups drops them all.
@property (nonatomic, readonly, copy) NSArray<NSArray<NSValue *> *> *groups;
/// The number of groups of each match, 0 without groups.
@property (nonatomic, readonly) NSUInteger groupCount;
/// The color of a match where no group is.
@property (class, nonatomic, readonly) NSColor *color;
/// The colors of the groups by number, round; a group inside another shows its own color.
@property (class, nonatomic, readonly) NSArray<NSColor *> *groupColors;

/// Sets the matches with their groups: `groups` is empty or has one element of the same count for each match.
- (void)setRanges:(NSArray<NSValue *> *)ranges groups:(NSArray<NSArray<NSValue *> *> *)groups;
/// Sets the matches with their groups: `groupRanges` holds `groupCount` NSRanges for each match, in the order of `ranges`.
- (void)setRanges:(NSArray<NSValue *> *)ranges groupRanges:(NSData *)groupRanges groupCount:(NSUInteger)groupCount;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)removeAll;

/// Draws the highlights of the layout manager's text storage. Call after super's -drawBackgroundForGlyphRange:atPoint:.
+ (void)drawInLayoutManager:(NSLayoutManager *)layoutManager forGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin;

@end

NS_ASSUME_NONNULL_END
