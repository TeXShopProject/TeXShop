// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Text to put in place of a range. Becomes a struct in Swift.
NS_SWIFT_NAME(RegexFindReplacement)
@interface TSRegexFindReplacement : NSObject <NSCopying>

@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly, copy) NSString *string;

- (instancetype)initWithRange:(NSRange)range string:(NSString *)string NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
