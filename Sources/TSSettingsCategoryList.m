// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategoryList.h"
@implementation TSSettingsCategoryList
+ (instancetype)standardList
{
    return [[self alloc] initWithCategories:@[
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryGeneral symbolName:@"gearshape" color:NSColor.systemBlueColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryDocuments symbolName:@"doc" color:NSColor.systemBlueColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryEditor symbolName:@"text.cursor" color:NSColor.systemOrangeColor startsGroup:YES],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategorySpelling symbolName:@"text.badge.checkmark" color:NSColor.systemGreenColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryAppearance symbolName:@"paintpalette" color:NSColor.systemPinkColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryPreview symbolName:@"doc.richtext" color:NSColor.systemCyanColor startsGroup:YES],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryTypesetting symbolName:@"textformat" color:NSColor.systemPurpleColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryConsole symbolName:@"terminal" color:NSColor.systemGrayColor startsGroup:NO],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryKeyboard symbolName:@"keyboard" color:NSColor.systemOrangeColor startsGroup:YES],
        [[TSSettingsCategory alloc] initWithIdentifier:TSSettingsCategoryUpdates symbolName:@"arrow.triangle.2.circlepath" color:NSColor.systemBlueColor startsGroup:NO]]];
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
