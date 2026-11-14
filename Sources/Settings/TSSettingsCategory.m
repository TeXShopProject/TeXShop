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
TSSettingsCategoryID const TSSettingsCategoryKeyboard = @"keyboard";
TSSettingsCategoryID const TSSettingsCategoryGeneral = @"general";
TSSettingsCategoryID const TSSettingsCategoryDocuments = @"documents";
TSSettingsCategoryID const TSSettingsCategorySpelling = @"spelling";
TSSettingsCategoryID const TSSettingsCategoryAppearance = @"appearance";
TSSettingsCategoryID const TSSettingsCategoryUpdates = @"updates";
@implementation TSSettingsCategory
+ (instancetype)standardCategoryWithIdentifier:(TSSettingsCategoryID)identifier
{
    // Fixed sRGB palette and symbols from the reviewed SettingsPanelLab design.
    NSDictionary<NSString *, NSArray *> *design = @{
        @"general": @[@"gearshape", @0x888780, @NO],
        @"documents": @[@"doc.text", @0x378ADD, @NO],
        @"editor": @[@"character.cursor.ibeam", @0xBA7517, @YES],
        @"keyboard": @[@"keyboard", @0x5F5E5A, @NO],
        @"spelling": @[@"text.badge.checkmark", @0x639922, @NO],
        @"appearance": @[@"paintpalette", @0x7F77DD, @NO],
        @"preview": @[@"doc.text.magnifyingglass", @0xE24B4A, @YES],
        @"typesetting": @[@"hammer", @0x534AB7, @NO],
        @"console": @[@"terminal", @0x2C2C2A, @NO],
        @"updates": @[@"arrow.triangle.2.circlepath", @0x1D9E75, @YES]
    };
    NSArray *spec = design[identifier];
    if (spec == nil) [NSException raise:NSInvalidArgumentException format:@"Unknown settings category %@", identifier];
    NSUInteger rgb = [spec[1] unsignedIntegerValue];
    NSColor *color = [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
    return [[self alloc] initWithIdentifier:identifier symbolName:spec[0] color:color startsGroup:[spec[2] boolValue]];
}
- (instancetype)initWithIdentifier:(TSSettingsCategoryID)identifier symbolName:(NSString *)symbolName color:(NSColor *)color startsGroup:(BOOL)startsGroup
{
    self = [super init];
    if (self == nil) { return nil; }
    _identifier = [identifier copy]; _symbolName = [symbolName copy]; _color = [color copy];
    _startsGroup = startsGroup;
    return self;
}
@end
