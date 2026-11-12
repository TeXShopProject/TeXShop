// SPDX-License-Identifier: GPL-2.0-or-later
// Legacy KeyEquivalents uses one-based positions or localized menu titles.
// Those describe the menus as they were before 5.60: Open Style File then sat in
// the Help menu right after Show Help for Package, and the File menu had no such
// item. Positions are counted in that order, so the move does not shift them.
static NSString *const TSLegacyMovedItem = @"TSShortcut.displayStyleFile:.0";
static NSString *const TSLegacyMovedItemFormerAnchor = @"TSShortcut.displayHelpForPackage:.0";
static NSMenuItem *TSLegacyItemWithIdentifier(NSMenu *menu, NSString *identifier)
{
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.identifier isEqualToString:identifier]) return item;
        NSMenuItem *found = item.hasSubmenu ? TSLegacyItemWithIdentifier(item.submenu, identifier) : nil;
        if (found != nil) return found;
    }
    return nil;
}
static NSArray<NSMenuItem *> *TSLegacyItems(NSMenu *menu)
{
    NSMutableArray<NSMenuItem *> *items = [menu.itemArray mutableCopy];
    NSMenu *root = menu;
    while (root.supermenu != nil) root = root.supermenu;
    NSMenuItem *moved = TSLegacyItemWithIdentifier(root, TSLegacyMovedItem);
    if (moved == nil) return items;
    [items removeObjectIdenticalTo:moved];
    NSUInteger anchor = [items indexOfObjectPassingTest:^BOOL(NSMenuItem *item, NSUInteger index, BOOL *stop) {
        return [item.identifier isEqualToString:TSLegacyMovedItemFormerAnchor];
    }];
    if (anchor != NSNotFound) [items insertObject:moved atIndex:anchor + 1];
    return items;
}
// Titles of the Typeset menu's typesetting methods before 5.60 named them by
// what they do (Direct PDF, Via DVI), in every language.
static NSString *TSLegacyFormerTitleIdentifier(NSString *title)
{
    static NSDictionary<NSString *, NSString *> *identifiers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
        for (NSString *former in @[@"Pdftex", @"pdfTeX"]) map[former] = @"TSShortcut.doChooseMethod:.100";
        for (NSString *former in @[@"TeX and DVI", @"TeX und DVI", @"TeX y DVI", @"TeX et DVI", @"TeX e DVI", @"TeX en DVI", @"TeX + DVI", @"Tex și  DVI", @"TeX 和 DVI"]) map[former] = @"TSShortcut.doChooseMethod:.101";
        identifiers = map;
    });
    return identifiers[title];
}
static NSMenuItem *TSLegacyMenuItem(NSMenu *menu, id key)
{
    if (![key isKindOfClass:NSString.class] || menu == nil) return nil;
    NSArray<NSMenuItem *> *items = TSLegacyItems(menu);
    NSInteger index = [key integerValue];
    if (index == 0) {
        for (NSMenuItem *item in items) if ([item.title isEqualToString:key]) return item;
        NSMenuItem *titled = [menu itemWithTitle:key];
        if (titled != nil) return titled;
        NSString *identifier = TSLegacyFormerTitleIdentifier(key);
        if (identifier != nil) for (NSMenuItem *item in items) if ([item.identifier isEqualToString:identifier]) return item;
        return nil;
    }
    return index > 0 && index <= (NSInteger)items.count ? items[index - 1] : nil;
}
static void TSApplyLegacyKeyEquivalent(NSMenuItem *item, id value)
{
    if (item == nil || ![value isKindOfClass:NSArray.class] || [value count] < 3) return;
    id key = value[0];
    if (![key isKindOfClass:NSString.class] || ![value[1] respondsToSelector:@selector(boolValue)] || ![value[2] respondsToSelector:@selector(boolValue)]) return;
    NSEventModifierFlags flags = NSEventModifierFlagCommand | NSEventModifierFlagFunction;
    if ([value[1] boolValue]) flags |= NSEventModifierFlagOption;
    if ([value[2] boolValue]) flags |= NSEventModifierFlagControl;
    item.keyEquivalent = key; item.keyEquivalentModifierMask = flags;
}
static void TSApplyLegacyMenuKeys(NSMenu *mainMenu, NSDictionary *shortcuts)
{
    if (![shortcuts isKindOfClass:NSDictionary.class]) return;
    for (id menuKey in shortcuts) {
        NSMenu *menu = TSLegacyMenuItem(mainMenu, menuKey).submenu;
        id entries = shortcuts[menuKey];
        if (menu == nil || ![entries isKindOfClass:NSDictionary.class]) continue;
        for (id itemKey in entries) {
            NSMenuItem *item = TSLegacyMenuItem(menu, itemKey);
            id value = entries[itemKey];
            if ([value isKindOfClass:NSDictionary.class]) {
                for (id childKey in value) {
                    NSMenuItem *child = TSLegacyMenuItem(item.submenu, childKey);
                    // Preserve only the former first child (Toggle On/Off).
                    // The removed editor remains inert compatibility data.
                    if ([item.identifier isEqualToString:@"TSShortcut.changeAutoComplete:.0"] && !item.hasSubmenu && [childKey isKindOfClass:NSString.class]) {
                        NSSet<NSString *> *oldTitles = [NSSet setWithArray:@[@"Activar/desactivar",@"Activer/Désactiver",@"Alternar Ligar/Desligar",@"Attiva/Disattiva",@"Ein/Aus",@"ON/OFF 切り替え",@"ON/OFF 교체",@"Toggle On/Off",@"打开/关闭"]];
                        if ([childKey isEqualToString:@"1"] || [oldTitles containsObject:childKey]) child = item;
                    }
                    TSApplyLegacyKeyEquivalent(child, value[childKey]);
                }
            } else TSApplyLegacyKeyEquivalent(item, value);
        }
    }
}
