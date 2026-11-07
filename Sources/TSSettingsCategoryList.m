// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategoryList.h"
@implementation TSSettingsCategoryList
+ (instancetype)standardList
{
    return [[self alloc] initWithCategories:@[
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategorySource symbolName:@"doc.text" color:NSColor.systemBlueColor startsGroup:NO legacyIndex:0],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryEditor symbolName:@"text.cursor" color:NSColor.systemOrangeColor startsGroup:NO legacyIndex:1],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryPreview symbolName:@"doc.richtext" color:NSColor.systemCyanColor startsGroup:YES legacyIndex:2],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryConsole symbolName:@"terminal" color:NSColor.systemGrayColor startsGroup:NO legacyIndex:3],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryTypesetting symbolName:@"textformat" color:NSColor.systemPurpleColor startsGroup:YES legacyIndex:4],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryEngines symbolName:@"gearshape.2" color:NSColor.systemGrayColor startsGroup:NO legacyIndex:5],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryMiscOne symbolName:@"slider.horizontal.3" color:NSColor.systemIndigoColor startsGroup:YES legacyIndex:6],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryMiscTwo symbolName:@"switch.2" color:NSColor.systemTealColor startsGroup:NO legacyIndex:7],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryThemes symbolName:@"paintpalette" color:NSColor.systemPinkColor startsGroup:NO legacyIndex:8]]];
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
