#import "TSSettingsSidebarRow.h"
#import "TSSettingsCategoryList.h"
@interface NSButtonCell (AuditedButtonType)
- (NSInteger)_buttonType;
@end
static void CountPresentedControls(NSView *view, NSUInteger counts[4]) {
    if (view.hidden || NSWidth(view.frame) < 0.5 || NSHeight(view.frame) < 0.5) return;
    if ([view.identifier hasPrefix:@"row.catalog."]) Check(NSHeight(view.frame)>=38,@"Catalog control rows preserve the 38 point minimum");
    if ([view isKindOfClass:NSSwitch.class]) {
        counts[0]++;
        Check(((NSSwitch *)view).controlSize == NSControlSizeSmall, @"Every displayed on/off switch is small");
    }
    if ([view isKindOfClass:NSButton.class]) {
        NSButtonCell *cell = ((NSButton *)view).cell;
        Check([cell respondsToSelector:@selector(_buttonType)], @"AppKit exposes the cell type used by the visual audit");
        NSInteger type = [cell _buttonType];
        if (type == NSButtonTypeSwitch) counts[1]++;
        if (type == NSButtonTypeRadio) counts[2]++;
    }
    if ([view isKindOfClass:NSMatrix.class]) counts[3]++;
    for (NSView *child in view.subviews) CountPresentedControls(child, counts);
}
static void CheckOwnerPresentation(TSSettingsWindowController *shell) {
    for(TSSettingsCategory *category in [TSSettingsCategoryList standardList].categories){
        NSString *title=[fixture localizedStringForKey:category.identifier value:nil table:@"SettingsCategories"];
        for(NSNumber *width in @[@158,@188,@298]){
            NSTableCellView *cell=[TSSettingsSidebarRow cellForCategory:category title:title];
            CGFloat height=[TSSettingsSidebarRow heightForTitle:title cellWidth:width.doubleValue];
            cell.frame=NSMakeRect(0,0,width.doubleValue,height);[cell layoutSubtreeIfNeeded];
            NSTextField *label=cell.textField;label.font=[NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];[cell layoutSubtreeIfNeeded];
            // Measure the constrained table width, not AppKit’s temporary intrinsic cell expansion.
            CGFloat textWidth=width.doubleValue-40;
            NSSize natural=[title boundingRectWithSize:NSMakeSize(textWidth,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:label.font}].size;
            Check(label.maximumNumberOfLines==2 && label.lineBreakMode==NSLineBreakByWordWrapping && natural.height<=NSHeight(label.bounds)+1 && NSHeight(label.bounds)<=height-5,@"Long localized sidebar names fit at every supported width");
            CGFloat single=[title sizeWithAttributes:@{NSFontAttributeName:label.font}].width;
            if([fixture.bundlePath.lastPathComponent isEqual:@"de.bundle"] && [category.identifier isEqual:@"spelling"])Check(single<=textWidth,@"German spelling title fits without splitting its word");
            Check(single>textWidth || height==30,[NSString stringWithFormat:@"One-line sidebar %@ width=%g label=%g natural=%g height=%g",title,width.doubleValue,textWidth,single,height]);
        }
    }
    NSDictionary *labels=[NSDictionary dictionaryWithContentsOfURL:[fixture URLForResource:@"SettingsCategories" withExtension:@"strings"]];
    Check(labels.count>100,@"Localized labels supply independent search sizing cases");
    for(NSString *text in labels.allValues)for(NSNumber *width in @[@158,@188,@298]){
        CGFloat total=10;
        for(NSNumber *size in @[@(NSFont.systemFontSize),@(NSFont.smallSystemFontSize)]){
            NSTextField *label=[NSTextField wrappingLabelWithString:text];label.font=[NSFont systemFontOfSize:size.doubleValue weight:NSFontWeightRegular];
            NSRect bounds=[label frameForAlignmentRect:NSMakeRect(0,0,width.doubleValue-16,1)];
            total+=ceil([label.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(bounds),CGFLOAT_MAX)].height);
        }
        Check([TSSettingsSidebarRow heightForSearchTitle:text categoryTitle:text cellWidth:width.doubleValue]==MAX(44,total),@"Search result height matches regular display");
    }
    for(NSString *query in @[@"utf",@"自動",@"Dock",[fixture localizedStringForKey:@"appearance" value:nil table:@"SettingsCategories"]]){
        [shell setSettingsSearchQuery:query];
        for(NSNumber *width in @[@158,@188,@298]){
            shell.categoryTable.tableColumns.firstObject.width=width.doubleValue;
            for(NSUInteger i=0;i<shell.searchResults.count;i++){
                NSTableCellView *cell=(NSTableCellView *)[shell tableView:shell.categoryTable viewForTableColumn:shell.categoryTable.tableColumns.firstObject row:i];
                CGFloat height=[shell tableView:shell.categoryTable heightOfRow:i];cell.frame=NSMakeRect(0,0,width.doubleValue,height);cell.textField.font=[NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];[cell layoutSubtreeIfNeeded];
                NSTextField *category=(NSTextField *)Find(cell,@"search.result.category");
                if (!shell.searchResults[i].targetIdentifier.length) {
                    Check(category==nil && cell.subviews.count==2,@"Category result has one name and its category icon");
                    continue;
                }
                Check(category.stringValue.length>0,@"Search result retains its category label");
                CGFloat requiredTextHeight=0;
                for(NSTextField *label in @[cell.textField,category]){
                    NSRect frame=[label alignmentRectForFrame:label.frame];
                    CGFloat needed=ceil([label.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(label.bounds),CGFLOAT_MAX)].height);
                    requiredTextHeight+=needed;
                    Check(NSMinY(frame)>=0 && NSMaxY(frame)<=height && NSHeight(label.bounds)>=needed,[NSString stringWithFormat:@"Wrapped search result names and categories fit the row: %@ label=%@ frame=%@ bounds=%@ required=%g height=%g",cell.textField.stringValue,label.stringValue,NSStringFromRect(frame),NSStringFromRect(label.bounds),needed,height]);
                }
                Check(fabs(height-MAX(44,requiredTextHeight+4+2+4))<0.01,[NSString stringWithFormat:@"Search result height matches regular display: %@ height=%g need=%g cell=%g requested=%g",cell.textField.stringValue,height,requiredTextHeight+10,NSWidth(cell.bounds),width.doubleValue]);
            }
        }
    }
    [shell setSettingsSearchQuery:@""];
    NSArray *notes=@[@[@"general",@"row.catalog.general.1.0"],@[@"editor",@"row.catalog.editor.0.1"],@[@"editor",@"row.catalog.editor.0.2"],@[@"editor",@"row.catalog.editor.0.4"],@[@"editor",@"row.catalog.editor.0.5"],@[@"editor",@"row.catalog.editor.3.1"],@[@"editor",@"row.catalog.editor.6.0"]];
    for(NSArray *entry in notes){NSView *row=Find([shell viewForCategoryIdentifier:entry[0]],entry[1]);Check(Find(row,@"note.catalog-row")!=nil,[NSString stringWithFormat:@"Per-document default explanation retained for %@",entry[1]]);}
    for(NSArray *entry in @[@[@"documents",@"row.catalog.documents.1.3"],@[@"typesetting",@"row.catalog.typesetting.9.0"]]){
        NSTextField *note=(NSTextField *)Find(Find([shell viewForCategoryIdentifier:entry[0]],entry[1]),@"note.catalog-row");Check(note.stringValue.length>20,@"Conversion settings include the approved explanation in each language");
    }
    NSDictionary *catalog = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[fixture URLForResource:@"SettingsCatalogReference" withExtension:@"json"]] options:0 error:NULL];
    Check([catalog[@"categories"] count] == 10, @"Independent approved catalog fixture is read");
    NSUInteger expected[4] = {0}, actual[4] = {0};
    for (NSDictionary *category in catalog[@"categories"]) {
        NSString *identifier = category[@"id"];
        Check([shell selectCategoryIdentifier:identifier], @"Catalog category exists");
        Check([shell.window.title isEqual:[fixture localizedStringForKey:identifier value:nil table:@"SettingsCategories"]],@"Every category including Keyboard updates the window title");
        [shell.window.contentView layoutSubtreeIfNeeded];
        NSView *pane = [identifier isEqual:@"keyboard"] ? [[shell valueForKey:@"keyboardPane"] view] : [shell viewForCategoryIdentifier:identifier];
        NSStackView *body = (NSStackView *)pane.subviews.firstObject;
        NSMutableArray<TSSettingsGroupView *> *groups = [NSMutableArray array];
        for (NSView *child in body.arrangedSubviews) if ([child isKindOfClass:TSSettingsGroupView.class]) [groups addObject:(TSSettingsGroupView *)child];
        Check(groups.count == [category[@"groups"] count], @"Catalog and rendered group counts agree");
        for (NSUInteger index = 0; index < groups.count; index++) {
            NSDictionary *reference = category[@"groups"][index];
            TSSettingsGroupView *group = groups[index];
            NSView *card=Find(group,@"card.background");
            Check(card != nil && !card.hidden && !card.hiddenOrHasHiddenAncestor && card.alphaValue>0.99 && NSWidth(card.bounds)>100 && NSHeight(card.bounds)>=38, @"Every catalog group has its visible rounded filled card");
            if ([fixture.bundlePath.lastPathComponent isEqual:@"ja.bundle"])
                Check([group.title isEqual:reference[@"title"]], [NSString stringWithFormat:@"Catalog group order/name %@ #%lu: %@",identifier,(unsigned long)index,group.title]);
            for (NSDictionary *row in reference[@"rows"]) {
                NSString *kind = row[@"kind"];
                if ([kind isEqual:@"switch"] || [kind isEqual:@"switchpopup"]) expected[0]++;
                if ([kind isEqual:@"radio"]) expected[2]++;
                if ([kind isEqual:@"checks"] || [kind isEqual:@"checkgrid"]) expected[1] += [row[@"choices"] count];
            }
        }
        CountPresentedControls(pane, actual);
    }
    Check(expected[0] == 50 && expected[1] == 15 && expected[2] == 2, @"Reference contains fifty switches and two exclusive spelling choices");
    // The reference describes checkbox labels as items in its checks/grid rows.
    Check(actual[0] == expected[0] && actual[1] == expected[1] && actual[2] == expected[2] && actual[3] == 0,
          [NSString stringWithFormat:@"Displayed controls: switches=%lu checks=%lu radios=%lu matrices=%lu",(unsigned long)actual[0],(unsigned long)actual[1],(unsigned long)actual[2],(unsigned long)actual[3]]);
    puts("PASS: independent catalog, group cards and actual visible control kinds");
}

static void CollectReviewControls(NSView *view, NSMutableArray *output) {
    if (view.hidden) return;
    if ([view isKindOfClass:NSPopUpButton.class]) {
        [output addObject:@{@"kind":@"choices", @"id":view.identifier ?: @"", @"values":((NSPopUpButton *)view).itemTitles}];
    } else if ([view isKindOfClass:NSButton.class] && ((NSButton *)view).title.length) {
        [output addObject:@{@"kind":@"button", @"id":view.identifier ?: @"", @"value":((NSButton *)view).title}];
    } else if ([view isKindOfClass:NSTextField.class] && !((NSTextField *)view).editable && ((NSTextField *)view).stringValue.length) {
        [output addObject:@{@"kind":@"label", @"id":view.identifier ?: @"", @"value":((NSTextField *)view).stringValue}];
    }
    for (NSView *child in view.subviews) CollectReviewControls(child,output);
}
static void CollectReviewRows(NSView *view, NSMutableArray *output) {
    if ([view.identifier hasPrefix:@"row.catalog."] || [view.identifier isEqual:@"DockIconChoices"]) {
        NSMutableArray *controls=[NSMutableArray array];CollectReviewControls(view,controls);
        [output addObject:@{@"id":view.identifier,@"controls":controls}];return;
    }
    for(NSView *child in view.subviews)CollectReviewRows(child,output);
}
static void WriteWordingReview(TSSettingsWindowController *shell, NSString *folder) {
    NSString *originalCategory=shell.history.currentIdentifier;
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    for(NSString *category in shell.categoryIdentifiers){[shell selectCategoryIdentifier:category];NSMutableArray *rows=[NSMutableArray array];CollectReviewRows([shell viewForCategoryIdentifier:category],rows);result[category]=rows;}
    [shell selectCategoryIdentifier:originalCategory];
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[folder stringByAppendingPathComponent:@"wording-review.json"] atomically:YES];
}
