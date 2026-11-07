// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface TSSettingsNavigationHistory : NSObject
@property (copy, readonly, nullable) NSString *currentIdentifier;
@property (copy, readonly, nullable) NSString *backIdentifier;
@property (copy, readonly, nullable) NSString *forwardIdentifier;
@property (readonly) NSUInteger count;
- (void)resetWithIdentifier:(NSString *)identifier;
- (void)visitIdentifier:(NSString *)identifier;
- (void)goBack;
- (void)goForward;
@end
NS_ASSUME_NONNULL_END
