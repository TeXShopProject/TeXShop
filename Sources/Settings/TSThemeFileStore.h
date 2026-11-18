// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface TSThemeFileStore : NSObject
@property (readonly, copy) NSURL *directory;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER;
- (nullable NSURL *)URLForTitle:(NSString *)title;
- (nullable NSDictionary<NSString *, id> *)readTitle:(NSString *)title;
- (BOOL)writeColors:(NSDictionary<NSString *, id> *)colors title:(NSString *)title error:(NSError * _Nullable * _Nullable)error;
// Writes the colors that differ between before and after into the theme file as it is at that moment, and keeps its
// other colors. Returns the colors written, or nil.
- (nullable NSDictionary<NSString *, id> *)writeChangesFrom:(NSDictionary<NSString *, id> *)before to:(NSDictionary<NSString *, id> *)after title:(NSString *)title error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
