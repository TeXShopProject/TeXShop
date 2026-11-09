// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
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
- (NSString *)displayStringFromDefaults:(NSUserDefaults *)defaults;
- (NSString *)displayStringForValue:(nullable TSPreferenceInputValue *)value;
@end
// Tracks actual edits, independently of first-responder/focus changes.
@interface TSPreferenceEditing : NSObject
@property (weak, readonly, nullable) NSControl *editedField;
- (void)markEdited:(NSControl *)field;
- (void)clear;
- (BOOL)commitField:(NSControl *)field rule:(TSPreferenceInput *)rule defaults:(NSUserDefaults *)defaults reflect:(BOOL)reflect sender:(NSObject *)sender;
- (void)restoreField:(NSControl *)field rule:(TSPreferenceInput *)rule defaults:(NSUserDefaults *)defaults;
@end
NS_ASSUME_NONNULL_END
