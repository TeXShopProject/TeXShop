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
// Source › Show Status Bar and Source › Highlight Index Entries are new in 6.00; positions saved before them skip
// them. So do the items that 6.00 added to
// the Edit menu: Copy with Style, Swap with Clipboard, Character Type Conversion and Unicode Normalization, and Marks,
// which moved there from Source › Command Completion.
static NSString *const TSLegacyStatusBarItem = @"TSShortcut.toggleStatusBar:.0";
static NSString *const TSLegacyIndexColorItem = @"TSShortcut.toggleIndexColor:.0";
static NSString *const TSLegacySwapItem = @"TSShortcut.exchangePaste:.0";
static BOOL TSLegacyIsAddedSubmenu(NSMenuItem *item)
{
    for (NSMenuItem *child in item.submenu.itemArray)
        if (child.action == NSSelectorFromString(@"copyWithLightTheme:") || child.action == NSSelectorFromString(@"convertCharacterType:") ||
            child.action == NSSelectorFromString(@"normalizeSelectedString:") || child.action == NSSelectorFromString(@"doNextBullet:"))
            return YES;
    return NO;
}
// Window › Fullscreen (Old Method) was removed in 6.00. It stood right before Enter Full Screen, so positions saved
// before that keep a place for it: its own key goes to an item that is not in any menu, and the keys of the items after it
// still reach the same items.
static NSString *const TSLegacyFullScreenItem = @"TSShortcut.toggleFullScreen:.0";
static void TSLegacyKeepRemovedFullscreen(NSMutableArray<NSMenuItem *> *items)
{
    NSUInteger fullScreen = [items indexOfObjectPassingTest:^BOOL(NSMenuItem *item, NSUInteger index, BOOL *stop) {
        return [item.identifier isEqualToString:TSLegacyFullScreenItem];
    }];
    if (fullScreen != NSNotFound) [items insertObject:[[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""] atIndex:fullScreen];
}
// 6.00 moved the older documents of the Help menu into its Older Documents submenu and George Grätzer's Short
// Course with the symbol tables into a submenu of their own, and removed Short Course Supplements --> Desktop;
// Spell Checking Help is added at launch, and the separator between Getting Started with TeXShop and the
// manual is gone. Positions saved before count the Help menu as it was (5.58),
// with the moved items in their former places, a place for the removed one, and without Spell Checking Help.
static NSString *const TSLegacyHelpMenuMarker = @"TSShortcut.displayThisRelease:.0";
static NSArray<NSString *> *TSLegacyFormerHelpMenu(void)
{
    return @[@"TSShortcut.displayThisRelease:.0", @"TSShortcut.displayChanges:.0", @"", @"TSShortcut.displayTeXLiveDocumentation:.0",
             @"TSShortcut.displayHelpForPackage:.0", @"", @"TSShortcut.displayGettingStartedTeXShop:.0", @"", @"TSShortcut.displayManual:.0", @"",
             @"TSShortcut.displayHTMLHelp:.0", @"TSShortcut.showHelp:.0", @"TSShortcut.displayFileEncoding:.0",
             @"TSShortcut.displayTipsandTricks:.0", @"TSShortcut.displayTeXShopConfusion:.0", @"TSShortcut.displayCommentLines:.0",
             @"TSShortcut.displayRecentTeXFonts:.0", @"TSShortcut.displayNotesonApplescript:.0", @"",
             @"TSShortcut.displayGettingStartedXeTeX:.0", @"", @"TSShortcut.displayGettingStartedLatex:.0",
             @"TSShortcut.displayShortCourse:.0", @"", @"TSShortcut.displayTables:.0"];
}
static NSMutableArray<NSMenuItem *> *TSLegacyFormerHelpItems(NSMenu *menu)
{
    // The Help menu itself has About This Release among its own items; the menus above it do not.
    BOOL helpMenu = NO;
    for (NSMenuItem *item in menu.itemArray)
        if ([item.identifier isEqualToString:TSLegacyHelpMenuMarker]) helpMenu = YES;
    if (!helpMenu) return nil;
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    for (NSString *identifier in TSLegacyFormerHelpMenu()) {
        NSMenuItem *item = identifier.length ? TSLegacyItemWithIdentifier(menu, identifier) : nil;
        // Separators and the removed item keep their places with an item that is not in any menu.
        [items addObject:item ?: [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""]];
    }
    return items;
}
static NSArray<NSMenuItem *> *TSLegacyItems(NSMenu *menu)
{
    NSMutableArray<NSMenuItem *> *items = TSLegacyFormerHelpItems(menu) ?: [menu.itemArray mutableCopy];
    [items filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSMenuItem *item, NSDictionary *bindings) {
        return ![item.identifier isEqualToString:TSLegacyStatusBarItem] && ![item.identifier isEqualToString:TSLegacyIndexColorItem] &&
               ![item.identifier isEqualToString:TSLegacySwapItem] &&
               !TSLegacyIsAddedSubmenu(item);
    }]];
    TSLegacyKeepRemovedFullscreen(items);
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
    // 6.00 marks the documents that are in English only, in every language; titles saved without the mark name the same items.
    for (NSString *mark in @[@" (Englisch)", @"（英語）", @" (영문)", @" (en inglés)", @" (en anglais)", @" (in inglese)", @" (Engels)",
                             @" (em inglês)", @" (în engleză)", @"（英文）"])
        if ([title hasSuffix:mark]) { title = [title substringToIndex:title.length - mark.length]; break; }
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \n"]];
    trimmed = [doubled stringByReplacingMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length) withTemplate:@" "];
    return [space stringByReplacingMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length) withTemplate:@""];
}
// Source › Command Completion was a submenu before 5.60 whose first item was
// Add Word; the Source menu now has that command itself in its place.
static NSString *const TSLegacyCompletionItem = @"TSShortcut.registerForCommandCompletion:.0";
// Titles that no longer exist but still name an item: the Typeset menu's
// typesetting methods before 5.60 named them by what they do (Direct PDF,
// Via DVI), the former Command Completion submenu, and the two syntax
// highlighting items of the Source menu before 6.00, in every language, and
// the Japanese TeX Live Documentation item before 6.00.
static NSString *TSLegacyFormerTitleIdentifier(NSString *title)
{
    static NSDictionary<NSString *, NSString *> *identifiers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
        for (NSString *former in @[@"Pdftex", @"pdfTeX"]) map[TSLegacyComparableTitle(former)] = @"TSShortcut.doChooseMethod:.100";
        for (NSString *former in @[@"TeX and DVI", @"TeX und DVI", @"TeX y DVI", @"TeX et DVI", @"TeX e DVI", @"TeX en DVI", @"TeX + DVI", @"Tex și  DVI", @"TeX 和 DVI"]) map[TSLegacyComparableTitle(former)] = @"TSShortcut.doChooseMethod:.101";
        for (NSString *former in @[@"Command Completion", @"Vervollständigung", @"Compleción de comandos ", @"Compleción de comandos", @"Commande de complètement", @"Completamento comandi", @"コマンド補完", @"명령 완성", @"Aanvullen", @"Completion", @"Completar", @"Completare", @"命令补全"]) map[TSLegacyComparableTitle(former)] = TSLegacyCompletionItem;
        // Show Syntax Color and Syntax Color expl3 Code before 6.00, in every language.
        for (NSString *former in @[@"Afficher la coloration syntaxique", @"Colorazione sintassi", @"Exibir destaque de sintaxe", @"Mostrar resaltado de sintaxis", @"Show Syntax Color", @"Syntaxhervorhebung anzeigen", @"Toggle Syntax Color", @"显示语法高亮", @"구문색상 끄기/켜기"]) map[TSLegacyComparableTitle(former)] = @"TSShortcut.toggleSyntaxColor:.14";
        for (NSString *former in @[@"Coloration syntaxique du code expl3", @"Colorazione sintassi codice expl3", @"Coloração de sintaxe do código expl3", @"Código exp da cor da sintaxe", @"Sintaxis de código expl3", @"Sintaxă Cod expl culoare", @"Syntax Color expl3 Code", @"Syntaxis Kleur expl3-code", @"expl3 구문 강조", @"expl3-Syntax farblich hervorheben"]) map[TSLegacyComparableTitle(former)] = @"TSShortcut.toggleExplColor:.0";
        // Help menu titles corrected in 6.00.
        map[TSLegacyComparableTitle(@"最近使用的TeX字体")] = @"TSShortcut.displayRecentTeXFonts:.0";
        map[TSLegacyComparableTitle(@"魔术行; 隐藏设置")] = @"TSShortcut.displayCommentLines:.0";
        map[TSLegacyComparableTitle(@"Primeiros passos com o TexShop")] = @"TSShortcut.displayGettingStartedTeXShop:.0";
        map[TSLegacyComparableTitle(@"Curso rápido de símbolos de tabelas")] = @"TSShortcut.displayTables:.0";
        map[TSLegacyComparableTitle(@"Exibir ajuda para o pacote")] = @"TSShortcut.displayHelpForPackage:.0";
        map[TSLegacyComparableTitle(@"Raccourcis clavier et autres par Herbert Schulz.")] = @"TSShortcut.displayTeXShopConfusion:.0";
        map[TSLegacyComparableTitle(@"Introductie symbooltabellen")] = @"TSShortcut.displayTables:.0";
        for (NSString *former in @[@"TeXShop Hilfspalette", @"TeXShopヘルプパネル", @"TeXShop 도움말 패널"])
            map[TSLegacyComparableTitle(former)] = @"TSShortcut.showHelp:.0";
        // George Grätzer's Short Course, the symbol tables and TeXShop Feature Confusion, in every language, as 5.58 and
        // 6.00 beta 9 named them; the course and the tables are now in a submenu named like the course was.
        for (NSString *former in @[@"George Grätzer's Short Course", @"Curso corto de George Grätzer", @"Cours allégé de George Grätzer",
                                   @"George Grätzer によるショートコース", @"George Grätzer 짧은 입문서", @"George Grätzers korte handleiding",
                                   @"Curso rápido do George Grätzer", @"George Grätzer 的快速教程", @"George Grätzers Kurzkurs",
                                   @"Corso breve di George Grätzer", @"George Grätzerによるショートコース", @"Curso breve de George Grätzer",
                                   @"Cursul scurt al lui George Grätzer", @"George Grätzer的快速教程"])
            map[TSLegacyComparableTitle(former)] = @"TSShortcut.displayShortCourse:.0";
        for (NSString *former in @[@"Short Course Symbol Tables", @"Tablas de símbolos del curso", @"Tables des symboles de LaTeX", @"記号一覧",
                                   @"기호 일람", @"快速教程符号表", @"Kurzkurs-Symboltabellen", @"Tabelle dei simboli del corso breve",
                                   @"Symbooltabellen van de korte handleiding", @"Tabelas de símbolos do curso breve", @"Tabelas de símbolos do curso rápido",
                                   @"Tabele de simboluri pentru cursul scurt"])
            map[TSLegacyComparableTitle(former)] = @"TSShortcut.displayTables:.0";
        for (NSString *former in @[@"TeXShop Feature Confusion", @"TeXShop Funktionsbeschreibung", @"Confusiones entre utilidades de TeXShop",
                                   @"TeXShop の様々な補完機能の解説", @"TeXShopの様々な補完機能の解説", @"단축키, 매크로, 자동완성에 대하여", @"Características do TeXShop",
                                   @"TeXShop 功能答疑", @"TeXShop功能答疑", @"Raccourcis clavier et autres", @"Chiarimenti sulle funzioni di TeXShop",
                                   @"Verwarrende TeXShop-functies", @"Confusões entre funcionalidades do TeXShop", @"Confuzii privind funcțiile TeXShop"])
            map[TSLegacyComparableTitle(former)] = @"TSShortcut.displayTeXShopConfusion:.0";
        // TeX Live Documentation in Japanese before 6.00, written without the space.
        map[TSLegacyComparableTitle(@"TeXLiveドキュメント（英語）")] = @"TSShortcut.displayTeXLiveDocumentation:.0";
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
    // As recording refuses them (TSShortcutStore isAllowedKey:), a saved key never takes Tab, Escape or
    // another control character, which command completion and the mark keys own, or Delete.
    if ([key length] > 0) {
        unichar c = [key characterAtIndex:0];
        if (c < 0x20 || c == 0x7f) return;
    }
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
            } else {
                // A key saved for an item that is a submenu now was for the document it opened then (George
                // Grätzer's Short Course): it goes to that document, in the submenu. A submenu takes no key itself.
                if (item.hasSubmenu) {
                    NSString *identifier = TSLegacyFormerTitleIdentifier(itemKey);
                    item = identifier != nil ? TSLegacyItemWithIdentifier(menu, identifier) : nil;
                }
                TSApplyLegacyKeyEquivalent(item, value);
            }
        }
    }
}
