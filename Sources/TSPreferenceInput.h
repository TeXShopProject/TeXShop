// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSPreferenceKey.h"
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TSPreferenceInputKind) {
    TSPreferenceInputText,
    TSPreferenceInputInteger,
    TSPreferenceInputPercentage
};
@interface TSPreferenceInputValue : NSObject
@property (readonly, copy, nullable) NSString *textValue;
@property (readonly, copy, nullable) NSNumber *numberValue;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
// Stores the validated value and returns whether the effective value changed.
- (BOOL)storeInDefaults:(NSUserDefaults *)defaults forKey:(TSPreferenceKey)key;
@end

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
- (nullable TSPreferenceInputValue *)validatedValue:(NSString *)text;
- (NSString *)displayStringForValue:(nullable TSPreferenceInputValue *)value;
@end
NS_ASSUME_NONNULL_END
