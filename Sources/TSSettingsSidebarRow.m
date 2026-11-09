// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsSidebarRow.h"
#import "TSPrefPaneLayout.h"
@implementation TSSettingsSidebarRow
+ (CGFloat)heightForTitle:(NSString *)title cellWidth:(CGFloat)width
{
    CGFloat available = MAX(1, width - 40);
    NSRect text = [title boundingRectWithSize:NSMakeSize(available, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular]}];
    return MAX(30, ceil(NSHeight(text)) + 6);
}
+ (NSTableCellView *)cellForCategory:(TSSettingsCategory *)category title:(NSString *)title
{
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    NSTextField *label = [NSTextField wrappingLabelWithString:title];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.maximumNumberOfLines = 2;
    label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textField = label;
    TSSettingsIconView *icon = [[TSSettingsIconView alloc] initWithSymbolName:category.symbolName color:category.color size:22];
    icon.translatesAutoresizingMaskIntoConstraints = NO; icon.accessibilityElement = NO;
    [cell addSubview:icon]; [cell addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6], [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor constant:0],
        [icon.widthAnchor constraintEqualToConstant:22], [icon.heightAnchor constraintEqualToConstant:22],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4], [label.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor]]];
    return cell;
}
// Measure the same regular font used by the displayed item name.
+ (CGFloat)heightForSearchTitle:(NSString *)title categoryTitle:(NSString *)categoryTitle cellWidth:(CGFloat)width
{
    CGFloat available=MAX(1,width-16);
    CGFloat height=10;
    NSArray *texts=@[title,categoryTitle];
    NSArray *fonts=@[[NSFont systemFontOfSize:NSFont.systemFontSize], [NSFont systemFontOfSize:NSFont.smallSystemFontSize]];
    for(NSUInteger i=0;i<texts.count;i++) {
        NSTextField *label=[NSTextField wrappingLabelWithString:texts[i]];
        label.font=fonts[i];
        // Constraints use alignment rectangles; NSTextField adds its cell insets.
        CGFloat cellWidth=NSWidth([label frameForAlignmentRect:NSMakeRect(0,0,available,1)]);
        height+=ceil([label.cell cellSizeForBounds:NSMakeRect(0,0,cellWidth,CGFLOAT_MAX)].height);
    }
    return MAX(44,height);
}
+ (NSTableCellView *)cellForSearchTitle:(NSString *)title categoryTitle:(NSString *)categoryTitle
{
    NSTableCellView *cell = [NSTableCellView new];
    NSTextField *name = [NSTextField wrappingLabelWithString:title];
    NSTextField *category = [NSTextField wrappingLabelWithString:categoryTitle];
    name.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    category.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    category.textColor = NSColor.secondaryLabelColor;
    category.identifier=@"search.result.category";
    for (NSTextField *label in @[name, category]) {
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        label.lineBreakMode = NSLineBreakByWordWrapping;
        [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cell addSubview:label];
        [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8], [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8]]];
    }
    [NSLayoutConstraint activateConstraints:@[[name.topAnchor constraintEqualToAnchor:cell.topAnchor constant:4], [category.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2], [category.bottomAnchor constraintLessThanOrEqualToAnchor:cell.bottomAnchor constant:-4]]];
    cell.textField = name;
    cell.toolTip = [NSString stringWithFormat:@"%@ — %@", title, categoryTitle];
    cell.accessibilityLabel = cell.toolTip;
    return cell;
}
@end
