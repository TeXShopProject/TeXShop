// SPDX-License-Identifier: GPL-2.0-or-later
// Final categories reuse the localized controls and their original typed owners.
// Moving a view never copies its value or changes its persistence action.
@interface TSSettingsPaneComposer : NSObject
+ (NSDictionary<TSSettingsCategoryID, NSViewController *> *)compose:(NSArray<TSPrefPaneController *> *)panes preferences:(TSPreferences *)preferences;
@end
@implementation TSSettingsPaneComposer
+ (NSBox *)mergeGroups:(NSArray<NSBox *> *)groups title:(NSString *)title identifier:(NSString *)identifier preserveSubheadings:(BOOL)preserve
{
    NSBox *merged = [self group:title identifier:identifier rows:@[]];
    NSStackView *destination = [self requireView:merged.contentView.subviews.firstObject ofClass:NSStackView.class];
    for (NSBox *group in groups) {
        [self requireView:group ofClass:NSBox.class];
        NSStackView *source = [self requireView:group.contentView.subviews.firstObject ofClass:NSStackView.class];
        for (NSView *row in [source.arrangedSubviews copy]) {
            if (!preserve && [row.identifier hasPrefix:@"heading."]) continue;
            [row removeFromSuperview];
            [destination addArrangedSubview:row];
            [row.widthAnchor constraintEqualToAnchor:destination.widthAnchor].active = YES;
        }
        [group removeFromSuperview];
    }
    return merged;
}

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
+ (id)requireView:(NSView *)view ofClass:(Class)expected
{
    if (![view isKindOfClass:expected]) [NSException raise:NSInternalInconsistencyException format:@"Expected %@ for %@", NSStringFromClass(expected), view.identifier];
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
+ (NSBox *)group:(NSString *)title identifier:(NSString *)identifier rows:(NSArray<TSSettingsControlRow *> *)rows
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
    for (TSSettingsControlRow *row in rows) {
        for (NSView *control in row.controls) {
            [control removeFromSuperview];
            [control removeConstraints:control.constraints];
        }
        [items addObject:[TSPrefPaneLayout viewForRow:row]];
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
    [self splitMatrix:[self requireView:take(@"621") ofClass:NSMatrix.class] identifiers:@[@"settings.cell.839", @"settings.cell.cgA-o7-Bdw", @"settings.cell.f1k-jx-ley", @"settings.cell.840", @"settings.cell.841", @"settings.cell.842", @"settings.cell.843", @"settings.cell.844", @"settings.cell.845", @"settings.cell.846", @"settings.cell.XoX-gZ-pO3", @"settings.cell.PhR-Vr-jce", @"settings.cell.CPb-hk-Gqb"] into:views];
    [self splitMatrix:[self requireView:take(@"cp7-bc-avh") ofClass:NSMatrix.class] identifiers:@[@"settings.cell.teg-0p-Q8J", @"settings.cell.3eF-XA-ahc", @"settings.cell.8Wq-gx-FqO"] into:views];
    NSMutableDictionary<NSString *, NSView *> *custom = [NSMutableDictionary dictionary];
    TSSettingsControlRow *(^row)(NSArray<NSView *> *, NSUInteger) = ^TSSettingsControlRow *(NSArray<NSView *> *controls, NSUInteger indent) {
        return [[TSSettingsControlRow alloc] initWithControls:controls indentation:indent];
    };
    custom[@"editor-defaults"] = [self group:text(@"Defaults for New Documents") identifier:@"group.editor-defaults" rows:@[row(@[take(@"cell.839")], 0), row(@[take(@"cell.f1k-jx-ley")], 0), row(@[take(@"cell.845")], 0)]];
    custom[@"editor-behavior"] = [self group:text(@"Editor") identifier:@"group.editor-behavior" rows:@[row(@[take(@"cell.844")], 0), row(@[take(@"cell.846")], 0), row(@[take(@"cell.XoX-gZ-pO3")], 0), row(@[take(@"cell.CPb-hk-Gqb")], 0), row(@[take(@"3gb-2l-vK7")], 0), row(@[take(@"9oZ-Jg-MfD")], 0), row(@[take(@"cell.cgA-o7-Bdw")], 0)]];
    custom[@"parens"] = [self group:text(@"Matching Brackets") identifier:@"group.parens" rows:@[row(@[take(@"cell.840")], 0)]];
    custom[@"spelling-common"] = [self group:text(@"Spelling While Typing") identifier:@"group.spelling-common" rows:@[row(@[take(@"cell.841")], 0), row(@[take(@"cell.PhR-Vr-jce")], 0)]];
    NSButton *aware = [self requireView:take(@"ts-aware-spelling") ofClass:NSButton.class];
    [aware setButtonType:NSButtonTypeRadio]; aware.title = text(@"Use LaTeX-aware spell checking (recommended)");
    NSButton *legacy = [NSButton radioButtonWithTitle:text(@"Use legacy spell checking") target:preferences action:@selector(legacySpellCheckPressed:)];
    legacy.identifier = @"settings.legacy-spelling"; preferences.legacySpellCheckButton = legacy;
    custom[@"spelling-method"] = [self group:text(@"LaTeX Spell Checking") identifier:@"group.spelling-method" rows:@[row(@[aware], 0), row(@[take(@"ts-edit-spelling")], 1), row(@[legacy], 0), row(@[take(@"cell.teg-0p-Q8J")], 1), row(@[take(@"cell.3eF-XA-ahc")], 1), row(@[take(@"cell.8Wq-gx-FqO")], 1)]];
    NSButton *bindings = [NSButton buttonWithTitle:text(@"Edit Key Bindings…") target:preferences action:@selector(editKeyBindings:)];
    bindings.identifier = @"settings.edit-bindings";
    bindings.toolTip = text(@"Edits the shared file for all documents. The checkbox sets the default for new documents.");
    custom[@"bindings"] = [self group:[NSString stringWithFormat:@"%@ — %@", text(@"Key Bindings"), text(@"Defaults for New Documents")] identifier:@"group.bindings" rows:@[row(@[take(@"cell.842"), bindings], 0)]];
    NSButton *completion = [NSButton buttonWithTitle:text(@"Edit Command Completion…") target:nil action:@selector(openCommandCompletionList:)];
    completion.identifier = @"settings.edit-completion";
    NSTextField *triggerLabel = [NSTextField labelWithString:text(@"Completion trigger")];
    triggerLabel.identifier = @"settings.completion-trigger-label";
    custom[@"completion"] = [self group:text(@"Command Completion") identifier:@"group.completion" rows:@[
        row(@[triggerLabel, take(@"926")], 0), row(@[take(@"cell.843")], 0), row(@[completion], 0)]];
    [triggerLabel.widthAnchor constraintEqualToConstant:170].active = YES;
    custom[@"windows"] = [self group:text(@"Source and Preview Windows") identifier:@"group.windows" rows:@[row(@[take(@"G6V-Sw-jFT"),take(@"MBq-SG-G54")], 0), row(@[take(@"iRm-g2-CpD"),take(@"zvK-4Q-HJ5")], 1)]];
    NSButton *help = [NSButton buttonWithTitle:text(@"Comment Lines and Hidden Settings") target:preferences action:@selector(displayCommentLines:)]; help.identifier = @"settings.hidden-settings-help";
    custom[@"advanced"] = [self group:text(@"Advanced") identifier:@"group.advanced" rows:@[row(@[help], 0)]];
    if (themes == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing appearance settings"];
    custom[@"themes"] = themes;
    NSBox *(^merge)(NSArray<NSString *> *, NSString *, NSString *, BOOL) = ^NSBox *(NSArray<NSString *> *keys, NSString *title, NSString *identifier, BOOL subheadings) {
        NSMutableArray<NSBox *> *groups = [NSMutableArray array];
        for (NSString *key in keys) [groups addObject:[self requireView:take(key) ofClass:NSBox.class]];
        return [self mergeGroups:groups title:text(title) identifier:identifier preserveSubheadings:subheadings];
    };
    NSView *encodingOption = take(@"5xa-en-KkV");
    NSView *oldEncodingRow = views[@"row.settings.5xa-en-KkV"];
    [oldEncodingRow removeFromSuperview];
    custom[@"encoding"] = merge(@[@"262", @"03p-fB-1K3"], @"Encoding", @"group.encoding", NO);
    NSStackView *encodingRows = [self requireView:((NSBox *)custom[@"encoding"]).contentView.subviews.firstObject ofClass:NSStackView.class];
    NSView *newEncodingRow = [TSPrefPaneLayout viewForRow:row(@[encodingOption], 0)];
    [encodingRows addArrangedSubview:newEncodingRow]; [newEncodingRow.widthAnchor constraintEqualToAnchor:encodingRows.widthAnchor].active = YES;
    custom[@"saving"] = merge(@[@"5ba-33-JZx", @"314"], @"Saving Documents", @"group.saving", NO);
    custom[@"page-display"] = merge(@[@"329", @"111", @"501"], @"Page Display", @"group.page-display", YES);
    custom[@"pdf-interaction"] = merge(@[@"342", @"228", @"330"], @"PDF Interaction", @"group.pdf-interaction", YES);
    custom[@"pdf-appearance"] = merge(@[@"5HT-3x-Zr6", @"386", @"447"], @"PDF Appearance", @"group.pdf-appearance", YES);
    custom[@"html-preview"] = merge(@[@"YrC-m9-abH", @"p2D-Mi-Gyc"], @"HTML Preview", @"group.html-preview", YES);
    custom[@"typesetting-defaults"] = merge(@[@"183", @"188", @"675"], @"Typesetting Defaults", @"group.typesetting-defaults", YES);
    custom[@"synchronization"] = merge(@[@"823", @"W5U-9S-4OG"], @"Synchronization", @"group.synchronization", YES);
    custom[@"tools"] = merge(@[@"1020", @"1027", @"SXg-YM-OVa", @"163-F5-v8Z", @"SS5-tZ-cDa"], @"Tools", @"group.tools", YES);
    // Each original group is assigned exactly once; split groups are listed above.
    NSDictionary<TSSettingsCategoryID, NSArray<NSString *> *> *mapping = @{
        TSSettingsCategoryGeneral: @[@"236", @"aig-4m-gAG", @"19", @"585", @"Kin-Cw-xVc", @"advanced"],
        TSSettingsCategoryDocuments: @[@"encoding", @"saving"],
        TSSettingsCategoryEditor: @[@"editor-defaults", @"editor-behavior", @"4a3-VM-Tgq", @"Gj7-Yx-1Hv", @"eIA-mh-q2u", @"parens", @"934", @"935", @"933", @"cSu-im-H1E", @"DU3-gi-QzY"],
        TSSettingsCategorySpelling: @[@"spelling-common", @"ENd-QB-0Uf", @"spelling-method"],
        TSSettingsCategoryAppearance: @[@"14", @"themes"],
        TSSettingsCategoryPreview: @[@"windows", @"47", @"page-display", @"pdf-interaction", @"555", @"pdf-appearance", @"html-preview"],
        TSSettingsCategoryTypesetting: @[@"typesetting-defaults", @"synchronization", @"215", @"54", @"200", @"Eb6-59-PxD", @"vEF-zd-SJl", @"tools"],
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
