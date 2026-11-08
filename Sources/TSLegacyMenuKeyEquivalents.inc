// SPDX-License-Identifier: GPL-2.0-or-later
// Legacy KeyEquivalents uses one-based positions or localized menu titles.
static NSMenuItem *TSLegacyMenuItem(NSMenu *menu, id key)
{
    if (![key isKindOfClass:NSString.class]) return nil;
    NSInteger index = [key integerValue];
    if (index == 0) return [menu itemWithTitle:key];
    return index > 0 && index <= menu.numberOfItems ? [menu itemAtIndex:index - 1] : nil;
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
