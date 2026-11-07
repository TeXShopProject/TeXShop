// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategory.h"
TSSettingsCategoryID const TSSettingsCategorySource = @"source";
TSSettingsCategoryID const TSSettingsCategoryEditor = @"editor";
TSSettingsCategoryID const TSSettingsCategoryPreview = @"preview";
TSSettingsCategoryID const TSSettingsCategoryConsole = @"console";
TSSettingsCategoryID const TSSettingsCategoryTypesetting = @"typesetting";
TSSettingsCategoryID const TSSettingsCategoryEngines = @"engines";
TSSettingsCategoryID const TSSettingsCategoryMiscOne = @"misc-1";
TSSettingsCategoryID const TSSettingsCategoryMiscTwo = @"misc-2";
TSSettingsCategoryID const TSSettingsCategoryThemes = @"themes";
@implementation TSSettingsCategory
- (instancetype)initWithIdentifier:(TSSettingsCategoryID)identifier symbolName:(NSString *)symbolName color:(NSColor *)color startsGroup:(BOOL)startsGroup legacyIndex:(NSUInteger)legacyIndex
{
    self = [super init];
    if (self == nil) { return nil; }
    _identifier = [identifier copy]; _symbolName = [symbolName copy]; _color = [color copy];
    _startsGroup = startsGroup; _legacyIndex = legacyIndex;
    return self;
}
@end
