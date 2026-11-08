// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategoryList.h"
@implementation TSSettingsCategoryList
+ (instancetype)standardList
{
    return [[self alloc] initWithCategories:@[
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategorySource symbolName:@"doc.text" color:NSColor.systemBlueColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryEditor symbolName:@"text.cursor" color:NSColor.systemOrangeColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryPreview symbolName:@"doc.richtext" color:NSColor.systemCyanColor startsGroup:YES],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryConsole symbolName:@"terminal" color:NSColor.systemGrayColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryTypesetting symbolName:@"textformat" color:NSColor.systemPurpleColor startsGroup:YES],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryEngines symbolName:@"gearshape.2" color:NSColor.systemGrayColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryMiscOne symbolName:@"slider.horizontal.3" color:NSColor.systemIndigoColor startsGroup:YES],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryMiscTwo symbolName:@"switch.2" color:NSColor.systemTealColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryThemes symbolName:@"paintpalette" color:NSColor.systemPinkColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryKeyboard symbolName:@"keyboard" color:NSColor.systemOrangeColor startsGroup:YES]]];
}
- (instancetype)initWithCategories:(NSArray<TSSettingsCategory *> *)categories
{
    self = [super init];
    if (self == nil) { return nil; }
    _categories = [categories copy];
    NSMutableArray<TSSettingsCategoryID> *identifiers = [NSMutableArray array];
    for (TSSettingsCategory *category in categories) { [identifiers addObject:category.identifier]; }
    _identifiers = [identifiers copy];
    return self;
}
- (TSSettingsCategory *)categoryForIdentifier:(TSSettingsCategoryID)identifier
{
    for (TSSettingsCategory *category in self.categories) {
        if ([category.identifier isEqualToString:identifier]) { return category; }
    }
    return nil;
}
@end
