// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef NSString *TSPreferenceKey NS_TYPED_EXTENSIBLE_ENUM;
typedef NS_ENUM(NSInteger, TSPreferenceInputKind) {
    TSPreferenceInputText,
    TSPreferenceInputInteger,
    TSPreferenceInputPercentage
};
@interface TSPreferenceInput : NSObject
@property (readonly, copy) TSPreferenceKey key;
@property (readonly) TSPreferenceInputKind kind;
@property (readonly) double minimum;
@property (readonly) double maximum;
@property (readonly) BOOL allowsEmpty;
@property (readonly, copy, nullable) NSNotificationName notification;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithKey:(TSPreferenceKey)key kind:(TSPreferenceInputKind)kind
                    minimum:(double)minimum maximum:(double)maximum allowsEmpty:(BOOL)allowsEmpty
               notification:(nullable NSNotificationName)notification NS_DESIGNATED_INITIALIZER;
- (nullable id)validatedValue:(NSString *)text;
- (NSString *)displayStringForValue:(id)value;
@end
NS_ASSUME_NONNULL_END
