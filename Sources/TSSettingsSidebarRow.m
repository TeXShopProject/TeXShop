// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsSidebarRow.h"
@interface TSSettingsIconView : NSView
@property (copy) NSString *symbol;
@property (strong) NSColor *tileColor;
@end
@implementation TSSettingsIconView
- (void)drawRect:(NSRect)dirtyRect
{
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6];
    NSColor *top = [self.tileColor blendedColorWithFraction:0.18 ofColor:NSColor.whiteColor] ?: self.tileColor;
    [[[NSGradient alloc] initWithStartingColor:top endingColor:self.tileColor] drawInBezierPath:tile angle:90];
    NSImage *symbol = [NSImage imageWithSystemSymbolName:self.symbol accessibilityDescription:nil];
    if (symbol == nil) { return; }
    NSImageSymbolConfiguration *configuration = [[NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightMedium]
        configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.whiteColor]]];
    NSImage *image = [symbol imageWithSymbolConfiguration:configuration];
    if (image == nil || image.size.width <= 0 || image.size.height <= 0) return;
    CGFloat scale = MIN(18 / image.size.width, 18 / image.size.height);
    NSSize size = NSMakeSize(image.size.width * scale, image.size.height * scale);
    [image drawInRect:NSMakeRect(NSMidX(self.bounds)-size.width/2,NSMidY(self.bounds)-size.height/2,size.width,size.height)];
}
@end
@implementation TSSettingsSidebarRow
+ (NSTableCellView *)cellForCategory:(TSSettingsCategory *)category title:(NSString *)title
{
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    NSTextField *label = [NSTextField wrappingLabelWithString:title];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.maximumNumberOfLines = 2;
    label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    label.lineBreakMode = NSLineBreakByWordWrapping;
    cell.textField = label;
    TSSettingsIconView *icon = [TSSettingsIconView new]; icon.symbol = category.symbolName; icon.tileColor = category.color;
    icon.translatesAutoresizingMaskIntoConstraints = NO; icon.accessibilityElement = NO;
    BOOL startsGroup = category.startsGroup;
    if (startsGroup) {
        NSBox *separator = [NSBox new]; separator.boxType = NSBoxSeparator;
        separator.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:separator];
        [NSLayoutConstraint activateConstraints:@[[separator.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
            [separator.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-6],
            [separator.topAnchor constraintEqualToAnchor:cell.topAnchor constant:3]]];
    }
    [cell addSubview:icon]; [cell addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6], [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor constant:startsGroup ? 6 : 0],
        [icon.widthAnchor constraintEqualToConstant:28], [icon.heightAnchor constraintEqualToConstant:28],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4], [label.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor]]];
    return cell;
}
@end
