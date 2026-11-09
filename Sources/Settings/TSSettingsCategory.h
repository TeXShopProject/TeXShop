// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
typedef NSString *TSSettingsCategoryID NS_TYPED_ENUM;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategorySource;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryEditor;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryPreview;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryConsole;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryTypesetting;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryEngines;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryMiscOne;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryMiscTwo;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryThemes;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryKeyboard;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryGeneral;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryDocuments;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategorySpelling;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryAppearance;
FOUNDATION_EXPORT TSSettingsCategoryID const TSSettingsCategoryUpdates;
@interface TSSettingsCategory : NSObject
+ (instancetype)standardCategoryWithIdentifier:(TSSettingsCategoryID)identifier;
@property (copy, readonly) TSSettingsCategoryID identifier;
@property (copy, readonly) NSString *symbolName;
@property (copy, readonly) NSColor *color;
@property (readonly) BOOL startsGroup;
- (instancetype)initWithIdentifier:(TSSettingsCategoryID)identifier symbolName:(NSString *)symbolName color:(NSColor *)color startsGroup:(BOOL)startsGroup NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
