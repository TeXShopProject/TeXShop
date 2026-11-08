// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsStateStore.h"
@interface TSSettingsStateStore ()
@property (strong) NSUserDefaults *defaults;
@end
@implementation TSSettingsStateStore
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    self = [super init];
    if (self == nil) { return nil; }
    _defaults = defaults;
    return self;
}
- (TSSettingsCategoryID)selectedCategoryInIdentifiers:(NSArray<TSSettingsCategoryID> *)identifiers
{
    NSString *identifier = [self.defaults stringForKey:TSSettingsSelectedCategoryKey];
    if (identifier == nil || ![identifiers containsObject:identifier]) { return identifiers.firstObject ?: TSSettingsCategoryGeneral; }
    return identifier;
}
- (void)saveSelectedCategory:(TSSettingsCategoryID)identifier
{
    [self.defaults setObject:identifier forKey:TSSettingsSelectedCategoryKey];
}
@end
