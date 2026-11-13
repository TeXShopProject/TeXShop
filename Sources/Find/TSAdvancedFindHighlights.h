// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Adopted by a layout manager that already draws the search highlights after super's background (TSLayoutManager).
NS_SWIFT_NAME(AdvancedFindHighlightDrawing)
@protocol TSAdvancedFindHighlightDrawing <NSObject>
@end

/// The search highlights of one text storage (plan §6). They are not temporary attributes: the ranges are kept here
/// and drawn by the layout manager over the background that is already there, so nothing underneath is overwritten
/// or lost when they are removed. Every view of the storage (a split window) shows them.
NS_SWIFT_NAME(AdvancedFindHighlights)
@interface TSAdvancedFindHighlights : NSObject

/// The highlights of `storage`, made on first use.
+ (instancetype)highlightsForTextStorage:(NSTextStorage *)storage;
+ (nullable instancetype)existingHighlightsForTextStorage:(NSTextStorage *)storage;

@property (nonatomic, readonly, weak) NSTextStorage *textStorage;
/// Sorted, without overlaps. Edits move the ranges after them and drop the ones they touch.
@property (nonatomic, copy) NSArray<NSValue *> *ranges;
@property (class, nonatomic, readonly) NSColor *color;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (void)removeAll;

/// Draws the highlights of the layout manager's text storage. Call after super's -drawBackgroundForGlyphRange:atPoint:.
+ (void)drawInLayoutManager:(NSLayoutManager *)layoutManager forGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin;

@end

NS_ASSUME_NONNULL_END
