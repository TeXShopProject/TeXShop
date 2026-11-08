// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsNavigationHistory.h"
@interface TSSettingsNavigationHistory ()
@property (strong) NSMutableArray<TSSettingsCategoryID> *entries;
@property NSUInteger position;
@end
@implementation TSSettingsNavigationHistory
- (instancetype)init
{
    self = [super init];
    if (self == nil) { return nil; }
    _entries = [NSMutableArray array];
    return self;
}
- (id)copyWithZone:(NSZone *)zone
{
    TSSettingsNavigationHistory *copy = [[[self class] allocWithZone:zone] init];
    copy.entries = [self.entries mutableCopy]; copy.position = self.position;
    return copy;
}
- (NSString *)currentIdentifier { return self.entries.count == 0 ? nil : self.entries[self.position]; }
- (NSString *)backIdentifier { return self.position == 0 ? nil : self.entries[self.position - 1]; }
- (NSString *)forwardIdentifier { return self.position + 1 >= self.entries.count ? nil : self.entries[self.position + 1]; }
- (NSUInteger)count { return self.entries.count; }
- (void)resetWithIdentifier:(NSString *)identifier { [self.entries removeAllObjects]; [self.entries addObject:identifier]; self.position = 0; }
- (void)visitIdentifier:(NSString *)identifier
{
    TSSettingsCategoryID current = self.currentIdentifier;
    if (current != nil && [identifier isEqualToString:current]) { return; }
    if (self.position + 1 < self.entries.count)
        [self.entries removeObjectsInRange:NSMakeRange(self.position + 1, self.entries.count - self.position - 1)];
    [self.entries addObject:identifier];
    if (self.entries.count > 50) [self.entries removeObjectAtIndex:0];
    self.position = self.entries.count - 1;
}
- (void)goBack { if (self.backIdentifier != nil) self.position--; }
- (void)goForward { if (self.forwardIdentifier != nil) self.position++; }
@end
