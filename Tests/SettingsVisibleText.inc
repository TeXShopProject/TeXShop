// Collect the displayed production panes, not their localization source tables.
// Values belonging to the user and live command rows have separate contracts.
static void CollectSettingsVisibleText(NSView *view, NSString *category, NSMutableArray *records) {
    if (view.hidden) return;
    BOOL userData=[view.accessibilityIdentifier isEqual:@"settings.user-data"];
    void (^record)(NSString *,NSString *)=^(NSString *text,NSString *role) {
        if (text.length) [records addObject:@{@"category":category,@"id":view.identifier ?: @"",@"role":role,@"text":text}];
    };
    if ([view isKindOfClass:NSTableView.class]) {
        for (NSTableColumn *column in ((NSTableView *)view).tableColumns) record(column.title,@"column");
        return; // Menu command names are runtime data, not settings labels.
    }
    if ([view isKindOfClass:NSPopUpButton.class]) {
        if (!userData) for (NSString *title in ((NSPopUpButton *)view).itemTitles) record(title,@"choice");
    } else if ([view isKindOfClass:NSButton.class]) {
        record(((NSButton *)view).title,@"button");
    } else if ([view isKindOfClass:NSTextField.class]) {
        NSTextField *field=(NSTextField *)view;
        if (!userData && !field.editable) record(field.stringValue,@"label");
        record(field.placeholderString,@"placeholder");
    } else if ([view isKindOfClass:NSSegmentedControl.class]) {
        NSSegmentedControl *control=(NSSegmentedControl *)view;
        for (NSInteger i=0;i<control.segmentCount;i++) record([control labelForSegment:i],@"segment");
    }
    for (NSView *child in view.subviews) CollectSettingsVisibleText(child,category,records);
}
