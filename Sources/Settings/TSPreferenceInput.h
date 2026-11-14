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
// An empty field removes the value set, so that the registered default applies; the field then
// stays empty and shows the default as its placeholder. The default typed out is not stored either.
@property (readonly) BOOL restoresDefaultWhenEmpty;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithKey:(TSPreferenceKey)key kind:(TSPreferenceInputKind)kind
                    minimum:(double)minimum maximum:(double)maximum allowsEmpty:(BOOL)allowsEmpty
               notification:(nullable NSNotificationName)notification NS_DESIGNATED_INITIALIZER;
- (instancetype)initRestoringDefaultForKey:(TSPreferenceKey)key;
- (nullable TSPreferenceInputValue *)validatedValue:(NSString *)text;
// Stores the value and returns whether the effective value changed.
- (BOOL)storeValue:(TSPreferenceInputValue *)value inDefaults:(NSUserDefaults *)defaults;
- (NSString *)displayStringFromDefaults:(NSUserDefaults *)defaults;
- (NSString *)displayStringForValue:(nullable TSPreferenceInputValue *)value;
@end
// The registered default of a text setting, or nil.
FOUNDATION_EXPORT NSString * _Nullable TSPreferenceRegisteredText(NSUserDefaults *defaults, TSPreferenceKey key);
// The text a field shows for a setting whose empty field stands for its default: the value set, or nothing while the
// default applies.
FOUNDATION_EXPORT NSString *TSPreferenceTextBesideDefault(NSUserDefaults *defaults, TSPreferenceKey key);
// Keeps typing in a whole-number field to digits (full-width digits become
// ASCII). Any text that reaches the end of editing is passed on unchanged, so
// TSPreferenceInput still decides whether it is valid. The minimum and maximum
// of the rule are kept for the stepper beside the field.
@interface TSIntegerInputFormatter : NSNumberFormatter
- (instancetype)initWithInput:(TSPreferenceInput *)input;
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
