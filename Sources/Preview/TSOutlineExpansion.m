/*
 * TSOutlineExpansion.m
 */

#import "TSOutlineExpansion.h"

static NSString *const TSOutlineKeySeparator = @"\x1E";

@implementation TSOutlineExpansion
{
    __weak NSOutlineView *_outlineView;
    NSMutableSet<NSString *> *_expandedKeys;
    BOOL _reloading;
}

- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView
{
    self = [super init];
    if (self) {
        _outlineView = outlineView;
        _expandedKeys = [NSMutableSet set];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(itemDidExpand:)
                       name:NSOutlineViewItemDidExpandNotification object:outlineView];
        [center addObserver:self selector:@selector(itemDidCollapse:)
                       name:NSOutlineViewItemDidCollapseNotification object:outlineView];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSet<NSString *> *)expandedKeys
{
    return [_expandedKeys copy];
}

+ (NSString *)titleOfItem:(id)item
{
    NSString *title = [item respondsToSelector:@selector(label)] ? [item label] : nil;
    return title ?: @"";
}

+ (NSString *)keyForItem:(id)item inOutlineView:(NSOutlineView *)outlineView
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (id current = item; current != nil; current = [outlineView parentForItem:current]) {
        id parent = [outlineView parentForItem:current];
        NSString *title = [self titleOfItem:current];
        NSInteger index = [outlineView childIndexForItem:current];
        NSInteger occurrence = 0;
        for (NSInteger i = 0; i < index; i++)
            if ([[self titleOfItem:[outlineView child:i ofItem:parent]] isEqualToString:title])
                occurrence++;
        [parts insertObject:[NSString stringWithFormat:@"%ld\x1F%@", (long)occurrence, title] atIndex:0];
    }
    return [parts componentsJoinedByString:TSOutlineKeySeparator];
}

- (void)itemDidExpand:(NSNotification *)notification
{
    if (_reloading)
        return;
    id item = notification.userInfo[@"NSObject"];
    if (item == nil)
        return;
    [_expandedKeys addObject:[[self class] keyForItem:item inOutlineView:_outlineView]];
    // Entries that were open inside this one before it was closed open with it,
    // as NSOutlineView does for items it already knows.
    [self expandRememberedChildrenOf:item];
}

- (void)itemDidCollapse:(NSNotification *)notification
{
    if (_reloading)
        return;
    id item = notification.userInfo[@"NSObject"];
    if (item == nil)
        return;
    // Closing an entry also reports its open entries as closed, after the entry
    // itself is marked closed. They open again with it, so keep them, unless
    // Option is held, which closes everything inside.
    id parent = [_outlineView parentForItem:item];
    BOOL closingAll = ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
    if (parent != nil && ![_outlineView isItemExpanded:parent] && !closingAll)
        return;
    [_expandedKeys removeObject:[[self class] keyForItem:item inOutlineView:_outlineView]];
}

- (void)expandRememberedChildrenOf:(nullable id)item
{
    NSOutlineView *outlineView = _outlineView;
    NSInteger count = [outlineView numberOfChildrenOfItem:item];
    for (NSInteger i = 0; i < count; i++) {
        id child = [outlineView child:i ofItem:item];
        if (![outlineView isExpandable:child])
            continue;
        if (![_expandedKeys containsObject:[[self class] keyForItem:child inOutlineView:outlineView]])
            continue;
        BOOL wasReloading = _reloading;
        _reloading = YES;
        [outlineView expandItem:child];
        _reloading = wasReloading;
        [self expandRememberedChildrenOf:child];
    }
}

- (void)reloadOutline
{
    NSClipView *clipView = _outlineView.enclosingScrollView.contentView;
    [self reloadOutlineScrollingTo:clipView.bounds.origin];
}

- (void)reloadOutlineScrollingTo:(NSPoint)origin
{
    NSOutlineView *outlineView = _outlineView;
    if (outlineView == nil)
        return;
    NSClipView *clipView = outlineView.enclosingScrollView.contentView;

    _reloading = YES;
    [outlineView reloadData];
    [self expandRememberedChildrenOf:nil];
    _reloading = NO;

    if (clipView != nil) {
        // The top of the outline is above 0 by the height of the column header
        // and the scroll view's insets, so let the clip view keep the position
        // within the outline as it is now. A position above 0 is the top: the
        // nib leaves the clip view at the height its header had there, which is
        // lower than the header shown now, and the drawer never moves it.
        NSRect bounds = clipView.bounds;
        bounds.origin = origin;
        if (origin.y < 0)
            bounds.origin.y = -1e6;
        bounds = [clipView constrainBoundsRect:bounds];
        [clipView scrollToPoint:bounds.origin];
        [outlineView.enclosingScrollView reflectScrolledClipView:clipView];
    }
}

// The pane of the drawer's split view that holds the outline, and that split view.
- (NSSplitView *)splitViewAroundOutline:(NSView **)pane
{
    for (NSView *view = _outlineView; view.superview != nil; view = view.superview) {
        if ([view.superview isKindOfClass:[NSSplitView class]]) {
            if (pane) *pane = view;
            return (NSSplitView *)view.superview;
        }
    }
    return nil;
}

- (NSDictionary *)restorableState
{
    NSOutlineView *outlineView = _outlineView;
    if (outlineView == nil)
        return @{};
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"expanded"] = [[_expandedKeys allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSClipView *clipView = outlineView.enclosingScrollView.contentView;
    if (clipView != nil)
        state[@"scrollY"] = @(clipView.bounds.origin.y);
    NSView *pane = nil;
    NSSplitView *split = [self splitViewAroundOutline:&pane];
    if (split != nil && split.subviews.count >= 2) {
        NSRect first = split.subviews[0].frame, second = split.subviews[1].frame;
        CGFloat one = split.isVertical ? NSWidth(first) : NSHeight(first);
        CGFloat two = split.isVertical ? NSWidth(second) : NSHeight(second);
        if (one + two > 0 && split.subviews[0] == pane)
            state[@"share"] = @(one / (one + two));
    }
    return state;
}

- (void)restoreState:(NSDictionary *)state
{
    if (![state isKindOfClass:[NSDictionary class]] || state.count == 0 || _outlineView == nil)
        return;
    NSArray *expanded = state[@"expanded"];
    if ([expanded isKindOfClass:[NSArray class]]) {
        [_expandedKeys removeAllObjects];
        for (id key in expanded)
            if ([key isKindOfClass:[NSString class]])
                [_expandedKeys addObject:key];
    }
    // The divider first, as the position that can be scrolled to depends on the room of the outline.
    NSNumber *share = state[@"share"];
    NSView *pane = nil;
    NSSplitView *split = [self splitViewAroundOutline:&pane];
    if ([share isKindOfClass:[NSNumber class]] && split != nil && split.subviews.count >= 2
        && split.subviews[0] == pane && share.doubleValue >= 0 && share.doubleValue <= 1) {
        CGFloat whole = (split.isVertical ? NSWidth(split.bounds) : NSHeight(split.bounds)) - split.dividerThickness;
        [split setPosition:round(whole * share.doubleValue) ofDividerAtIndex:0];
        [split adjustSubviews];
    }
    NSClipView *clipView = _outlineView.enclosingScrollView.contentView;
    NSPoint origin = clipView.bounds.origin;
    NSNumber *scrollY = state[@"scrollY"];
    if ([scrollY isKindOfClass:[NSNumber class]])
        origin.y = scrollY.doubleValue;
    [self reloadOutlineScrollingTo:origin];
}

@end
