//
//  TSToolbar.m
//  TeXShop
//
//  Created by Richard Koch on 3/27/11.
//  Copyright 2011 University of Oregon. All rights reserved.
//

#import "TSToolbar.h"

// On macOS 26 and later, neighboring bordered items share one piece of glass. When
// a window is just too narrow for such a group at the end of the toolbar, AppKit
// (seen on macOS 27.2) shows part of the group and then moves the whole group to the
// overflow menu, over and over, with nothing happening: the end of the toolbar
// flickers. The toolbar settles when the items it keeps differ in priority: the items
// after the last flexible space are kept before the others, or, without a flexible
// space, each item before the items on its left. An item keeps a higher priority of
// its own. Check after each major update of macOS whether this is still needed.
BOOL TSToolbarArrangesVisibilityPriorities(void)
{
    if (@available(macOS 26.0, *))
        return YES;
    return NO;
}

NSToolbarItemVisibilityPriority TSToolbarVisibilityPriority(NSUInteger index, NSInteger lastFlexibleSpace)
{
    if (lastFlexibleSpace < 0)
        return (NSToolbarItemVisibilityPriority)index;
    return (NSInteger)index > lastFlexibleSpace ? NSToolbarItemVisibilityPriorityHigh : NSToolbarItemVisibilityPriorityStandard;
}

@implementation TSToolbar {
    // The priority each item had before the toolbar gave it one.
    NSMapTable<NSToolbarItem *, NSNumber *> *_ownPriorities;
    NSArray<NSString *> *_arrangedIdentifiers;
    // Items announced as added, which may come into the list of items a little later.
    NSHashTable<NSToolbarItem *> *_comingItems;
    BOOL _arrangementPending;
}

- (instancetype)initWithIdentifier:(NSToolbarIdentifier)identifier
{
    self = [super initWithIdentifier:identifier];
    if (self && TSToolbarArrangesVisibilityPriorities()) {
        _ownPriorities = [NSMapTable weakToStrongObjectsMapTable];
        _comingItems = [NSHashTable weakObjectsHashTable];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(itemsWillChange:) name:NSToolbarWillAddItemNotification object:self];
        [center addObserver:self selector:@selector(itemsWillChange:) name:NSToolbarDidRemoveItemNotification object:self];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// An item is added before it is in the list of items: the priorities are given once the change is made.
- (void)itemsWillChange:(NSNotification *)notification
{
    NSToolbarItem *item = notification.userInfo[@"item"];
    if ([notification.name isEqual:NSToolbarWillAddItemNotification] && [item isKindOfClass:NSToolbarItem.class])
        [_comingItems addObject:item];
    [self arrangeVisibilityPrioritiesSoon:10];
}

- (void)arrangeVisibilityPrioritiesSoon:(NSInteger)tries
{
    if (_arrangementPending)
        return;
    _arrangementPending = YES;
    __weak TSToolbar *toolbar = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [toolbar arrangeVisibilityPrioritiesTrying:tries];
    });
}

- (void)arrangeVisibilityPrioritiesTrying:(NSInteger)tries
{
    _arrangementPending = NO;
    // A window about to close leaves its items alone; turned on again, validation gives the priorities.
    if (visibleOff) {
        [_comingItems removeAllObjects];
        return;
    }
    for (NSToolbarItem *item in _comingItems.allObjects) {
        if ([self.items indexOfObjectIdenticalTo:item] != NSNotFound)
            [_comingItems removeObject:item];
    }
    if (_comingItems.count > 0 && tries > 1) {
        [self arrangeVisibilityPrioritiesSoon:tries - 1];
        return;
    }
    [_comingItems removeAllObjects];
    [self arrangeVisibilityPriorities];
}

- (void)arrangeVisibilityPriorities
{
    NSArray<NSToolbarItem *> *items = self.items;
    NSInteger lastFlexibleSpace = -1;
    for (NSUInteger i = 0; i < items.count; i++)
        if ([items[i].itemIdentifier isEqual:NSToolbarFlexibleSpaceItemIdentifier])
            lastFlexibleSpace = (NSInteger)i;
    for (NSUInteger i = 0; i < items.count; i++) {
        NSToolbarItem *item = items[i];
        NSNumber *own = [_ownPriorities objectForKey:item];
        if (!own) {
            own = @(item.visibilityPriority);
            [_ownPriorities setObject:own forKey:item];
        }
        NSToolbarItemVisibilityPriority priority = MAX(TSToolbarVisibilityPriority(i, lastFlexibleSpace), own.integerValue);
        if (item.visibilityPriority != priority)
            item.visibilityPriority = priority;
    }
    _arrangedIdentifiers = [items valueForKey:@"itemIdentifier"];
}

// Items moved in the customization sheet are caught here if no notification told of them.
- (void)validateVisibleItems
{
    [super validateVisibleItems];
    if (_ownPriorities && !visibleOff && !_arrangementPending && ![[self.items valueForKey:@"itemIdentifier"] isEqual:_arrangedIdentifiers])
        [self arrangeVisibilityPriorities];
}

- (NSArray *)visibleItems
{
	if (visibleOff)
		return ([NSArray array]);
	else
		return ([super visibleItems]);
}

- (void)turnVisibleOff:(BOOL)value;
{
	visibleOff = value;
}

@end
