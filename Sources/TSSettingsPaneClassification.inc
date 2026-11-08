// SPDX-License-Identifier: GPL-2.0-or-later
// Final categories reuse the localized controls and their original typed owners.
// Moving a view never copies its value or changes its persistence action.
@interface TSSettingsPaneComposer : NSObject
+ (NSDictionary<TSSettingsCategoryID, NSViewController *> *)compose:(NSArray<TSPrefPaneController *> *)panes preferences:(TSPreferences *)preferences;
@end
@implementation TSSettingsPaneComposer
+ (void)collect:(NSView *)view into:(NSMutableDictionary<NSString *, NSView *> *)views
{
    NSString *identifier = view.identifier;
    if (identifier != nil) views[identifier] = view;
    for (NSView *child in view.subviews) [self collect:child into:views];
}
+ (NSView *)take:(NSString *)identifier from:(NSMutableDictionary<NSString *, NSView *> *)views
{
    NSView *view = views[identifier];
    if (view == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing category control %@", identifier];
    [views removeObjectForKey:identifier];
    [view removeFromSuperview];
    return view;
}
+ (void)splitMatrix:(NSMatrix *)matrix identifiers:(NSArray<NSString *> *)identifiers into:(NSMutableDictionary<NSString *, NSView *> *)views
{
    NSArray<NSCell *> *cells = [matrix.cells copy];
    if (cells.count != identifiers.count) [NSException raise:NSInternalInconsistencyException format:@"Unexpected settings matrix cells"];
    while (matrix.numberOfRows) [matrix removeRow:0];
    [matrix removeFromSuperview];
    for (NSUInteger index = 0; index < cells.count; index++) {
        NSButton *button = [NSButton new];
        button.cell = cells[index];
        button.identifier = identifiers[index];
        views[identifiers[index]] = button;
    }
}
+ (NSBox *)group:(NSString *)title identifier:(NSString *)identifier rows:(NSArray<NSArray<NSView *> *> *)rows indents:(NSIndexSet *)indents
{
    NSBox *box = [NSBox new]; box.title = title; box.identifier = identifier;
    [TSSettingsGroupStyle applyToBox:box]; box.accessibilityLabel = title;
    NSView *content = box.contentView;
    if (content == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing category group content"];
    NSMutableArray<NSView *> *items = [NSMutableArray array];
    NSTextField *heading = [NSTextField wrappingLabelWithString:title];
    heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    heading.identifier = [@"heading." stringByAppendingString:identifier];
    [items addObject:heading];
    NSUInteger index = 0;
    for (NSArray<NSView *> *controls in rows) {
        for (NSView *control in controls) {
            [control removeFromSuperview];
            [control removeConstraints:control.constraints];
            [TSPrefPaneLayout prepareControl:control];
        }
        NSStackView *body = [TSPrefPaneLayout stackWithViews:controls orientation:NSUserInterfaceLayoutOrientationHorizontal];
        NSView *row = [NSView new]; row.translatesAutoresizingMaskIntoConstraints = NO;
        row.identifier = [@"row." stringByAppendingString:controls.firstObject.identifier ?: @""];
        [row addSubview:body];
        [NSLayoutConstraint activateConstraints:@[
            [body.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:[indents containsIndex:index] ? 24 : 0],
            [body.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [body.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [row.heightAnchor constraintGreaterThanOrEqualToAnchor:body.heightAnchor],
            [row.heightAnchor constraintGreaterThanOrEqualToConstant:38]]];
        NSLayoutConstraint *height = [row.heightAnchor constraintEqualToConstant:0]; height.priority = 249; height.active = YES;
        [items addObject:row]; index++;
    }
    [TSPrefPaneLayout attachRows:items toView:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8],
        [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8],
        [content.topAnchor constraintEqualToAnchor:box.topAnchor constant:8],
        [content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8]]];
    return box;
}
+ (NSDictionary<TSSettingsCategoryID, NSViewController *> *)compose:(NSArray<TSPrefPaneController *> *)panes preferences:(TSPreferences *)preferences
{
    NSMutableDictionary<NSString *, NSView *> *views = [NSMutableDictionary dictionary];
    NSBundle *bundle = NSBundle.mainBundle;
    NSView *themes = nil;
    for (TSPrefPaneController *pane in panes) {
        [self collect:pane.view into:views];
        if (pane.nibBundle != nil) bundle = pane.nibBundle;
        if ([pane.categoryIdentifier isEqualToString:TSSettingsCategoryThemes]) themes = pane.view;
    }
    NSString *(^text)(NSString *) = ^NSString *(NSString *key) { return [bundle localizedStringForKey:key value:key table:@"Localizable"]; };
    NSView *(^take)(NSString *) = ^NSView *(NSString *key) { return [self take:[@"settings." stringByAppendingString:key] from:views]; };
    [self splitMatrix:(NSMatrix *)take(@"621") identifiers:@[@"settings.cell.839", @"settings.cell.cgA-o7-Bdw", @"settings.cell.f1k-jx-ley", @"settings.cell.840", @"settings.cell.841", @"settings.cell.842", @"settings.cell.843", @"settings.cell.844", @"settings.cell.845", @"settings.cell.846", @"settings.cell.XoX-gZ-pO3", @"settings.cell.PhR-Vr-jce", @"settings.cell.CPb-hk-Gqb"] into:views];
    [self splitMatrix:(NSMatrix *)take(@"cp7-bc-avh") identifiers:@[@"settings.cell.teg-0p-Q8J", @"settings.cell.3eF-XA-ahc", @"settings.cell.8Wq-gx-FqO"] into:views];
    NSMutableDictionary<NSString *, NSView *> *custom = [NSMutableDictionary dictionary];
    custom[@"editor-defaults"] = [self group:text(@"Defaults for New Documents") identifier:@"group.editor-defaults" rows:@[
        @[take(@"cell.839")], @[take(@"cell.f1k-jx-ley")], @[take(@"cell.845")]] indents:NSIndexSet.indexSet];
    custom[@"editor-behavior"] = [self group:text(@"Editor") identifier:@"group.editor-behavior" rows:@[@[take(@"cell.844")], @[take(@"cell.846")], @[take(@"cell.XoX-gZ-pO3")], @[take(@"cell.CPb-hk-Gqb")], @[take(@"3gb-2l-vK7")], @[take(@"9oZ-Jg-MfD")], @[take(@"cell.cgA-o7-Bdw")]] indents:NSIndexSet.indexSet];
    custom[@"parens"] = [self group:text(@"Matching Brackets") identifier:@"group.parens" rows:@[@[take(@"cell.840")]] indents:NSIndexSet.indexSet];
    custom[@"spelling-common"] = [self group:text(@"Spelling While Typing") identifier:@"group.spelling-common" rows:@[@[take(@"cell.841")], @[take(@"cell.PhR-Vr-jce")]] indents:NSIndexSet.indexSet];
    NSButton *aware = (NSButton *)take(@"ts-aware-spelling");
    [aware setButtonType:NSButtonTypeRadio]; aware.title = text(@"Use LaTeX-aware spell checking (recommended)");
    NSButton *legacy = [NSButton radioButtonWithTitle:text(@"Use legacy spell checking") target:preferences action:@selector(legacySpellCheckPressed:)];
    legacy.identifier = @"settings.legacy-spelling"; preferences.legacySpellCheckButton = legacy;
    NSMutableIndexSet *spellingIndents = [NSMutableIndexSet indexSetWithIndex:1]; [spellingIndents addIndexesInRange:NSMakeRange(3,3)];
    custom[@"spelling-method"] = [self group:text(@"LaTeX Spell Checking") identifier:@"group.spelling-method" rows:@[
        @[aware], @[take(@"ts-edit-spelling")], @[legacy], @[take(@"cell.teg-0p-Q8J")], @[take(@"cell.3eF-XA-ahc")], @[take(@"cell.8Wq-gx-FqO")]] indents:spellingIndents];
    NSButton *bindings = [NSButton buttonWithTitle:text(@"Edit Key Bindings…") target:preferences action:@selector(editKeyBindings:)];
    bindings.identifier = @"settings.edit-bindings";
    custom[@"bindings"] = [self group:text(@"Key Bindings") identifier:@"group.bindings" rows:@[@[take(@"cell.842"), bindings]] indents:NSIndexSet.indexSet];
    NSButton *completion = [NSButton buttonWithTitle:text(@"Edit Command Completion…") target:nil action:@selector(openCommandCompletionList:)];
    completion.identifier = @"settings.edit-completion";
    NSTextField *reservation = [NSTextField wrappingLabelWithString:text(@"When Tab triggers command completion, Tab is reserved for completion and cannot be assigned to a menu shortcut.")];
    reservation.identifier = @"settings.completion-reservation";
    custom[@"completion"] = [self group:text(@"Command Completion") identifier:@"group.completion" rows:@[@[take(@"926"), take(@"cell.843")], @[completion], @[reservation]] indents:NSIndexSet.indexSet];
    custom[@"windows"] = [self group:text(@"Source and Preview Windows") identifier:@"group.windows" rows:@[
        @[take(@"G6V-Sw-jFT"),take(@"MBq-SG-G54")], @[take(@"iRm-g2-CpD"),take(@"zvK-4Q-HJ5")]] indents:[NSIndexSet indexSetWithIndex:1]];
    NSButton *help = [NSButton buttonWithTitle:text(@"Comment Lines and Hidden Settings") target:preferences action:@selector(displayCommentLines:)]; help.identifier = @"settings.hidden-settings-help";
    custom[@"advanced"] = [self group:text(@"Advanced") identifier:@"group.advanced" rows:@[@[help]] indents:NSIndexSet.indexSet];
    if (themes == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing appearance settings"];
    custom[@"themes"] = themes;
    // Each original group is assigned exactly once; split groups are listed above.
    NSDictionary<TSSettingsCategoryID, NSArray<NSString *> *> *mapping = @{
        TSSettingsCategoryGeneral: @[@"236", @"aig-4m-gAG", @"19", @"585", @"Kin-Cw-xVc", @"advanced"],
        TSSettingsCategoryDocuments: @[@"262", @"5ba-33-JZx", @"03p-fB-1K3", @"314"],
        TSSettingsCategoryEditor: @[@"editor-defaults", @"editor-behavior", @"4a3-VM-Tgq", @"Gj7-Yx-1Hv", @"eIA-mh-q2u", @"parens", @"934", @"935", @"933", @"cSu-im-H1E", @"DU3-gi-QzY"],
        TSSettingsCategorySpelling: @[@"spelling-common", @"ENd-QB-0Uf", @"spelling-method"],
        TSSettingsCategoryAppearance: @[@"14", @"themes"],
        TSSettingsCategoryPreview: @[@"windows", @"47", @"329", @"342", @"111", @"501", @"228", @"330", @"555", @"5HT-3x-Zr6", @"386", @"447", @"YrC-m9-abH", @"p2D-Mi-Gyc"],
        TSSettingsCategoryTypesetting: @[@"183", @"188", @"675", @"823", @"W5U-9S-4OG", @"163-F5-v8Z", @"215", @"54", @"200", @"1020", @"1027", @"Eb6-59-PxD", @"vEF-zd-SJl", @"SXg-YM-OVa", @"SS5-tZ-cDa"],
        TSSettingsCategoryConsole: @[@"752", @"WQX-9X-AFi", @"772", @"828"],
        TSSettingsCategoryKeyboard: @[@"bindings", @"completion"],
        TSSettingsCategoryUpdates: @[@"e3h-Wk-X7D"]
    };
    NSMutableDictionary<TSSettingsCategoryID, NSViewController *> *result = [NSMutableDictionary dictionary];
    for (TSSettingsCategoryID category in mapping) {
        NSMutableArray<NSView *> *groups = [NSMutableArray array];
        for (NSString *key in mapping[category]) {
            NSView *group = custom[key];
            if (group != nil) { [custom removeObjectForKey:key]; [group removeFromSuperview]; }
            else group = take(key);
            [groups addObject:group];
        }
        NSViewController *controller = [[NSViewController alloc] initWithNibName:nil bundle:nil];
        controller.title = [bundle localizedStringForKey:category value:category table:@"SettingsCategories"];
        controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,700,600)]; controller.view.identifier = [@"category." stringByAppendingString:category];
        [TSPrefPaneLayout attachRows:groups toView:controller.view]; result[category] = controller;
    }
    return [result copy];
}
@end
