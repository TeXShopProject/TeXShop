// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
@implementation TSShortcutSearch
+ (NSArray<TSShortcutMatch *> *)matchesKey:(NSString *)key modifiers:(NSEventModifierFlags)flags store:(TSShortcutStore *)store macros:(NSArray<TSShortcutMacro *> *)macros {
    NSMutableArray<TSShortcutMatch *> *matches = [[store menuMatchesKey:key modifiers:flags excluding:nil] mutableCopy];
    // Reuse the same raw comparison and file-order ownership used by the macro editor.
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (TSShortcutMacro *macro in macros) {
        [candidates addObject:@{@"path":macro.path, @"key":macro.key, @"modifiers":@(macro.modifiers)}];
    }
    NSMutableIndexSet *inactive = [NSMutableIndexSet indexSet];
    for (NSDictionary *conflict in [store conflictsForMacroShortcuts:candidates]) { [inactive addIndex:[conflict[@"index"] unsignedIntegerValue]]; }
    NSDictionary *binding = TSBinding(key, flags);
    [macros enumerateObjectsUsingBlock:^(TSShortcutMacro *macro, NSUInteger index, BOOL *stop) {
        if (macro.key.length == 0 || ![TSBinding(macro.key, macro.modifiers) isEqual:binding]) { return; }
        [matches addObject:[[TSShortcutMatch alloc] initWithPath:macro.path menuItem:nil command:nil macro:macro winner:![inactive containsIndex:index]]];
    }];
    return [matches copy];
}
+ (NSArray<TSShortcutMatch *> *)matchesEvent:(NSEvent *)event store:(TSShortcutStore *)store macros:(NSArray<TSShortcutMacro *> *)macros {
    NSMutableArray<TSShortcutMatch *> *menus = [NSMutableArray array], *macroMatches = [NSMutableArray array];
    NSMutableSet<NSMenuItem *> *seenMenus = [NSMutableSet set];
    NSMutableSet<NSIndexPath *> *seenMacros = [NSMutableSet set];
    // These are only the recorder's spellings of this input. Ownership stays raw;
    // no restoration aliases or keyboard-layout comparison of assignments is used.
    for (NSDictionary *binding in TSEventBindings(event, [event charactersByApplyingModifiers:0])) {
        NSString *key = binding[@"key"] ?: @"";
        for (TSShortcutMatch *match in [self matchesKey:key modifiers:[binding[@"modifiers"] unsignedIntegerValue] store:store macros:macros]) {
            NSMenuItem *item = match.menuItem;
            TSShortcutMacro *macro = match.macro;
            if (item != nil && ![seenMenus containsObject:item]) {
                [seenMenus addObject:item]; [menus addObject:match];
            } else if (macro != nil && ![seenMacros containsObject:macro.indexPath]) {
                [seenMacros addObject:macro.indexPath]; [macroMatches addObject:match];
            }
        }
    }
    // Recorded and shifted input spellings are searched before the unshifted
    // fallback. Keep priority independent of deduplication used to gather results.
    NSArray<NSDictionary *> *primaryBindings = @[
        TSRecordedBinding(event, [event charactersByApplyingModifiers:0]),
        TSBinding(TSShortcutCharacterForEvent(event), event.modifierFlags)
    ];
    NSMapTable<NSMenuItem *, TSShortcutMatch *> *byItem = [NSMapTable strongToStrongObjectsMapTable];
    for (TSShortcutMatch *match in menus) { [byItem setObject:match forKey:match.menuItem]; }
    NSMutableDictionary<NSDictionary *, TSShortcutMatch *> *activeMacros = [NSMutableDictionary dictionary];
    for (TSShortcutMatch *match in macroMatches) {
        TSShortcutMacro *macro = match.macro;
        if (macro != nil && match.winner) { activeMacros[TSBinding(macro.key, macro.modifiers)] = match; }
    }
    NSMutableArray<TSShortcutMatch *> *orderedMenus = [NSMutableArray array];
    __block TSShortcutMatch *winner = nil;
    __block NSUInteger winningTier = NSUIntegerMax;
    // A raw-active macro competes at its live doMacro: item's position, not
    // after every menu. This affects search display only, never stored bindings.
    TSVisitMenu(store.menu, @"", ^(NSMenuItem *item, NSString *path) {
        TSShortcutMatch *match = [byItem objectForKey:item];
        if (match != nil) { [orderedMenus addObject:match]; }
        NSDictionary *binding = TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask);
        if (match == nil && item.action == TSMacroAction() && item.keyEquivalent.length > 0) {
            match = activeMacros[binding];
        }
        if (match == nil) { return; }
        NSUInteger tier = [primaryBindings containsObject:binding] ? 0 : 1;
        if (tier < winningTier) { winner = match; winningTier = tier; }
    });
    NSMutableArray<TSShortcutMatch *> *ordered = [NSMutableArray array];
    for (TSShortcutMatch *match in orderedMenus) {
        [ordered addObject:[[TSShortcutMatch alloc] initWithPath:match.path menuItem:match.menuItem command:match.command macro:nil winner:match == winner]];
    }
    for (TSShortcutMacro *macro in macros) {
        for (TSShortcutMatch *match in macroMatches) {
            if (match.macro != macro) { continue; }
            [ordered addObject:[[TSShortcutMatch alloc] initWithPath:match.path menuItem:nil command:nil macro:macro winner:match == winner]];
        }
    }
    return [ordered copy];
}
@end

