#import "TSSettingsSidebarRow.h"
#import "TSSettingsCategoryList.h"
@interface NSButtonCell (AuditedButtonType)
- (NSInteger)_buttonType;
@end
static void CountPresentedControls(NSView *view, NSUInteger counts[4]) {
    if (view.hidden || NSWidth(view.frame) < 0.5 || NSHeight(view.frame) < 0.5) return;
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
            NSTextField *label=cell.textField;label.font=[NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];[cell layoutSubtreeIfNeeded];
            // Measure the constrained table width, not AppKit’s temporary intrinsic cell expansion.
            CGFloat textWidth=width.doubleValue-40;
            NSSize natural=[title boundingRectWithSize:NSMakeSize(textWidth,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:label.font}].size;
            Check(label.maximumNumberOfLines==2 && label.lineBreakMode==NSLineBreakByWordWrapping && natural.height<=NSHeight(label.bounds)+1 && NSHeight(label.bounds)<=height-5,@"Long localized sidebar names fit at every supported width");
            CGFloat single=[title sizeWithAttributes:@{NSFontAttributeName:label.font}].width;
            Check(single>textWidth || height==30,[NSString stringWithFormat:@"One-line sidebar %@ width=%g label=%g natural=%g height=%g",title,width.doubleValue,textWidth,single,height]);
        }
    }
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
            Check(card != nil && !card.hidden && !card.hiddenOrHasHiddenAncestor && NSWidth(card.bounds)>100 && NSHeight(card.bounds)>=38, @"Every catalog group has its visible rounded filled card");
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
