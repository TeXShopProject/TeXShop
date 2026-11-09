// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategoryList.h"
@implementation TSSettingsCategoryList
+ (instancetype)standardList
{
    NSMutableArray<TSSettingsCategory *> *categories = [NSMutableArray array];
    for (TSSettingsCategoryID identifier in @[TSSettingsCategoryGeneral, TSSettingsCategoryDocuments, TSSettingsCategoryEditor, TSSettingsCategorySpelling, TSSettingsCategoryAppearance, TSSettingsCategoryPreview, TSSettingsCategoryTypesetting, TSSettingsCategoryConsole, TSSettingsCategoryKeyboard, TSSettingsCategoryUpdates]) {
        [categories addObject:[TSSettingsCategory standardCategoryWithIdentifier:identifier]];
    }
    return [[self alloc] initWithCategories:categories];
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
