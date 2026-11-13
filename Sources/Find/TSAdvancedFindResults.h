// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSRegexTextFind.h"

NS_ASSUME_NONNULL_BEGIN

/// One match of a "Find All".
NS_SWIFT_NAME(AdvancedFindResultItem)
@interface TSAdvancedFindResultItem : NSObject
/// The match and its groups when they were found: element 0 is the match, element k is group k
/// ({NSNotFound, 0} when the group did not take part).
@property (nonatomic, readonly, copy) NSArray<NSValue *> *foundRanges;
/// Where the match is now, moved by the edits since. An edit inside it makes it longer or shorter, an edit over
/// one end leaves the rest, an edit over all of it leaves an empty range where the edit ends (as OgreKit does).
@property (nonatomic, readonly) NSRange currentRange;
/// An edit touched the match: it may no longer match. The row is grayed, and still jumps to `currentRange`.
@property (nonatomic, readonly, getter=isStale) BOOL stale;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// The matches of a "Find All" in one text storage. They follow every edit of the text, as
/// OgreKit's do: matches after an edit move, a match the edit touched is adjusted and becomes stale.
/// With `updatesLive`, the search runs again shortly after the edits, with the same pattern and scope.
NS_SWIFT_NAME(AdvancedFindResults)
@interface TSAdvancedFindResults : NSObject

/// An item for every match of `find`, with its groups, or nil when cancelled. It uses Foundation only, so it can run
/// on any queue (a live update runs it on a background queue). `progress` is called now and then with how far the
/// search is and how many it found.
+ (nullable NSArray<TSAdvancedFindResultItem *> *)itemsOfFind:(TSRegexTextFind *)find
                                                  cancellation:(nullable BOOL (^)(void))isCancelled
                                                      progress:(nullable void (^)(double fraction, NSUInteger count))progress;
/// Searches `find`'s string, which must be the text of `storage` now.
- (instancetype)initWithTextStorage:(NSTextStorage *)storage find:(TSRegexTextFind *)find findString:(NSString *)findString;
/// The items already made by +itemsOfFind:… in the text of `storage` as it is now.
- (instancetype)initWithTextStorage:(NSTextStorage *)storage find:(TSRegexTextFind *)find findString:(NSString *)findString
                              items:(NSArray<TSAdvancedFindResultItem *> *)items NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly, weak) NSTextStorage *textStorage;
/// The find string as the user typed it, for the list to show.
@property (nonatomic, readonly, copy) NSString *findString;
@property (nonatomic, readonly) TSRegexFindPattern *pattern;
/// The ranges searched in, moved by the edits; nil for the whole text.
@property (nonatomic, readonly, copy, nullable) NSArray<NSValue *> *scopeRanges;
@property (nonatomic, readonly, copy) NSArray<TSAdvancedFindResultItem *> *items;
@property (nonatomic, readonly) NSUInteger staleCount;
/// The current ranges of the matches that are not stale, in order.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *currentRanges;

/// Turning it on searches again only when the text was edited since the last search.
@property (nonatomic) BOOL updatesLive;
/// Seconds between the last edit and the new search when `updatesLive` is on.
@property (nonatomic) NSTimeInterval liveUpdateDelay;
/// Called after the items moved, became stale or were found again.
@property (nonatomic, copy, nullable) void (^changeHandler)(TSAdvancedFindResults *results);

/// Searches the current text again, on a background queue; the items and `changeHandler` follow on the main thread.
/// A newer edit or search drops the result of an older one.
- (void)update;

/// The line of the match (1-based) in the current text.
- (NSUInteger)lineNumberOfItem:(TSAdvancedFindResultItem *)item;
/// The line of the match with a little text before it ("…" when cut), the match colored with `matchColor` and the
/// groups with `groupColors` (by group number, round), line breaks in the match shown as "⏎".
/// At most 30 characters before the match and 250 in all, as in OgreKit. A stale item shows the text there now,
/// in the tertiary label color without the match colors.
- (NSAttributedString *)lineTextOfItem:(TSAdvancedFindResultItem *)item
                            attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
                            matchColor:(NSColor *)matchColor
                           groupColors:(NSArray<NSColor *> *)groupColors;

@end

NS_ASSUME_NONNULL_END
