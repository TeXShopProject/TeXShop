/*
 * TSOutlineExpansion.h
 *
 * Keeps the open entries of the PDF outline in the Preview drawer
 * when the outline is rebuilt after typesetting.
 *
 * Typesetting replaces the PDF, so every PDFOutline item is new and an
 * NSOutlineView would show the outline fully collapsed again. This object
 * remembers each opened entry by its titles, from the top level down,
 * and opens the matching entries of the new outline again.
 */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSOutlineExpansion : NSObject

- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView;

/// Reloads the outline view, then opens the remembered entries again and
/// keeps the scroll position.
- (void)reloadOutline;

/// The key that identifies an outline entry across reloads: the title of
/// each entry from the top level down, with the position of the title
/// among siblings that have the same title.
+ (NSString *)keyForItem:(id)item inOutlineView:(NSOutlineView *)outlineView;

@property (readonly) NSSet<NSString *> *expandedKeys;

/// What the drawer shows of the outline, as a property list: the open entries, the scroll
/// position and the share of the drawer that the outline takes above the search results.
/// It is kept with a window's restorable state (#71).
- (NSDictionary *)restorableState;

/// Shows the outline as described by a state made by -restorableState, also for a PDF that is
/// not the one it was made from: entries that are no longer there stay closed.
- (void)restoreState:(nullable NSDictionary *)state;

@end

NS_ASSUME_NONNULL_END
