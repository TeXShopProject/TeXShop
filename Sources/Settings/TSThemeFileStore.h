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
@end
NS_ASSUME_NONNULL_END
