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
// Edit › Find › Find and Replace… was in the English (Base) menu only; the other languages' menus have it after Find…
// since 6.00, so positions saved for those menus skip it.
static NSString *const TSLegacyFindAndReplaceItem = @"TSShortcut.performTextFinderAction:.12";
/// Whether the MainMenu nib at `path` (the one the application loaded) had Find and Replace… before 6.00: the Base one.
static BOOL TSLegacyMenuPathHadFindAndReplace(NSString *path)
{
    return path == nil || [path containsString:@"/Base.lproj/"];
}
/// Whether the menu in use had Find and Replace… before 6.00; -1 until asked. The tests set it.
static int TSLegacyMenuHadFindAndReplace = -1;
static BOOL TSLegacySkipsFindAndReplace(void)
{
    if (TSLegacyMenuHadFindAndReplace < 0)
        TSLegacyMenuHadFindAndReplace = TSLegacyMenuPathHadFindAndReplace([NSBundle.mainBundle pathForResource:@"MainMenu" ofType:@"nib"]);
    return TSLegacyMenuHadFindAndReplace == 0;
}
static NSArray<NSMenuItem *> *TSLegacyItems(NSMenu *menu)
{
    NSMutableArray<NSMenuItem *> *items = [menu.itemArray mutableCopy];
    if (TSLegacySkipsFindAndReplace()) {
        NSUInteger added = [items indexOfObjectPassingTest:^BOOL(NSMenuItem *item, NSUInteger index, BOOL *stop) {
            return [item.identifier isEqualToString:TSLegacyFindAndReplaceItem];
        }];
        if (added != NSNotFound) [items removeObjectAtIndex:added];
    }
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
// Japanese and Chinese titles dropped the space between CJK and Latin text,
// as macOS does, and titles in several languages dropped a stray space at the
// start or end or a doubled one inside; titles saved before that still name the same items.
static NSString *TSLegacyComparableTitle(NSString *title)
{
    static NSRegularExpression *space, *doubled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *cjk = @"[\\x{3000}-\\x{30FF}\\x{3400}-\\x{9FFF}\\x{FF01}-\\x{FF60}]";
        NSString *pattern = [NSString stringWithFormat:@"(?<=%@) (?=[A-Za-z0-9])|(?<=[A-Za-z0-9]) (?=%@)", cjk, cjk];
        space = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
        doubled = [NSRegularExpression regularExpressionWithPattern:@" {2,}" options:0 error:NULL];
    });
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" "]];
    trimmed = [doubled stringByReplacingMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length) withTemplate:@" "];
    return [space stringByReplacingMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length) withTemplate:@""];
}
// Source › Command Completion was a submenu before 5.60 whose first item was
// Add Word; the Source menu now has that command itself in its place.
static NSString *const TSLegacyCompletionItem = @"TSShortcut.registerForCommandCompletion:.0";
// Titles that no longer exist but still name an item: the Typeset menu's
// typesetting methods before 5.60 named them by what they do (Direct PDF,
// Via DVI), and the former Command Completion submenu, in every language.
static NSString *TSLegacyFormerTitleIdentifier(NSString *title)
{
    static NSDictionary<NSString *, NSString *> *identifiers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
        for (NSString *former in @[@"Pdftex", @"pdfTeX"]) map[TSLegacyComparableTitle(former)] = @"TSShortcut.doChooseMethod:.100";
        for (NSString *former in @[@"TeX and DVI", @"TeX und DVI", @"TeX y DVI", @"TeX et DVI", @"TeX e DVI", @"TeX en DVI", @"TeX + DVI", @"Tex și  DVI", @"TeX 和 DVI"]) map[TSLegacyComparableTitle(former)] = @"TSShortcut.doChooseMethod:.101";
        for (NSString *former in @[@"Command Completion", @"Vervollständigung", @"Compleción de comandos ", @"Compleción de comandos", @"Commande de complètement", @"Completamento comandi", @"コマンド補完", @"명령 완성", @"Aanvullen", @"Completion", @"Completar", @"Completare", @"命令补全"]) map[TSLegacyComparableTitle(former)] = TSLegacyCompletionItem;
        identifiers = map;
    });
    return identifiers[TSLegacyComparableTitle(title)];
}
// An entry for the first item of the former Command Completion submenu, by
// position or by any title Add Word had, reaches the command. Its other items
// (Marks, the removed file editor) stay inert.
static BOOL TSLegacyIsFormerCompletionChild(NSMenuItem *item, id childKey)
{
    if (![item.identifier isEqualToString:TSLegacyCompletionItem] || item.hasSubmenu || ![childKey isKindOfClass:NSString.class]) return NO;
    NSSet<NSString *> *oldTitles = [NSSet setWithArray:@[@"Add Word", @"Wort hinzufügen", @"Añadir palabra", @"Ajouter un mot", @"Aggiungi comando", @"用語を追加", @"항목 추가", @"Voeg woord toe", @"Adicionar palavra", @"Adaugă un Cuvânt", @"新增单词"]];
    return [childKey isEqualToString:@"1"] || [oldTitles containsObject:childKey];
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
        NSString *comparable = TSLegacyComparableTitle(key);
        if (comparable.length > 0)
            for (NSMenuItem *item in items) if ([TSLegacyComparableTitle(item.title) isEqualToString:comparable]) return item;
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
                    if (TSLegacyIsFormerCompletionChild(item, childKey)) child = item;
                    TSApplyLegacyKeyEquivalent(child, value[childKey]);
                }
            } else TSApplyLegacyKeyEquivalent(item, value);
        }
    }
}
