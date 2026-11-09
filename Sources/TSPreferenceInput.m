// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceInput.h"
#import <math.h>
@interface TSPreferenceInputValue ()
- (instancetype)initWithText:(nullable NSString *)text number:(nullable NSNumber *)number;
@end
@implementation TSPreferenceInputValue
- (instancetype)initWithText:(nullable NSString *)text number:(nullable NSNumber *)number
{
    self = [super init];
    if (self != nil) { _textValue = [text copy]; _numberValue = [number copy]; }
    return self;
}
- (BOOL)storeInDefaults:(NSUserDefaults *)defaults forKey:(TSPreferenceKey)key
{
    NSObject *value = self.textValue ?: (NSObject *)self.numberValue;
    BOOL changed = ![[defaults objectForKey:key] isEqual:value];
    if (changed) [defaults setObject:value forKey:key];
    return changed;
}
@end

@implementation TSPreferenceInput
- (instancetype)initWithKey:(TSPreferenceKey)key kind:(TSPreferenceInputKind)kind
                    minimum:(double)minimum maximum:(double)maximum allowsEmpty:(BOOL)allowsEmpty
               notification:(nullable NSNotificationName)notification
{
    self = [super init];
    if (self == nil) return nil;
    _key = [key copy]; _kind = kind; _minimum = minimum; _maximum = maximum;
    _allowsEmpty = allowsEmpty; _notification = [notification copy];
    return self;
}
- (nullable TSPreferenceInputValue *)validatedValue:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (self.kind == TSPreferenceInputText) {
        if (!self.allowsEmpty && trimmed.length == 0) return nil;
        if ([trimmed rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
        return [[TSPreferenceInputValue alloc] initWithText:trimmed number:nil];
    }
    if (trimmed.length == 0) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    scanner.locale = NSLocale.currentLocale;
    double number;
    if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number)) return nil;
    number = MIN(self.maximum, MAX(self.minimum, number));
    if (self.kind == TSPreferenceInputInteger) return [[TSPreferenceInputValue alloc] initWithText:nil number:@((NSInteger)number)];
    return [[TSPreferenceInputValue alloc] initWithText:nil number:@(number / 100.0)];
}
- (NSString *)displayStringFromDefaults:(NSUserDefaults *)defaults
{
    // Restoration is based on this field's key, including empty/missing values.
    // Do not validate or clamp a previously stored value while restoring it.
    if (self.kind == TSPreferenceInputText) return [defaults stringForKey:self.key] ?: @"";
    NSObject *stored = [defaults objectForKey:self.key];
    NSNumber *number = [stored isKindOfClass:NSNumber.class] ? (NSNumber *)stored : nil;
    return [self displayStringForValue:[[TSPreferenceInputValue alloc] initWithText:nil number:number]];
}
- (NSString *)displayStringForValue:(nullable TSPreferenceInputValue *)value
{
    if (self.kind == TSPreferenceInputText) return value.textValue ?: @"";
    if (value.numberValue == nil) return @"";
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = NO;
    formatter.maximumFractionDigits = 6;
    NSNumber *number = self.kind == TSPreferenceInputPercentage ? @(value.numberValue.doubleValue * 100) : value.numberValue;
    return [formatter stringFromNumber:number] ?: @"";
}
@end

@interface TSPreferenceEditing ()
@property (weak, readwrite, nullable) NSControl *editedField;
@end
@implementation TSPreferenceEditing
- (void)markEdited:(NSControl *)field { self.editedField = field; }
- (void)clear { self.editedField = nil; }
- (BOOL)commitField:(NSControl *)field rule:(TSPreferenceInput *)rule defaults:(NSUserDefaults *)defaults reflect:(BOOL)reflect sender:(NSObject *)sender
{
    if (self.editedField != field) return YES;
    NSText *editor = field.currentEditor;
    TSPreferenceInputValue *value = [rule validatedValue:editor != nil ? editor.string : field.stringValue];
    if (value == nil) return NO;
    BOOL changed = [value storeInDefaults:defaults forKey:rule.key];
    field.stringValue = [rule displayStringForValue:value];
    if (editor != nil) editor.string = field.stringValue;
    self.editedField = nil;
    NSNotificationName notification = rule.notification;
    if (reflect && changed && notification != nil) [NSNotificationCenter.defaultCenter postNotificationName:notification object:sender];
    return YES;
}
- (void)restoreField:(NSControl *)field rule:(TSPreferenceInput *)rule defaults:(NSUserDefaults *)defaults
{
    NSString *original = [rule displayStringFromDefaults:defaults];
    field.stringValue = original;
    NSText *editor = field.currentEditor;
    if (editor != nil) editor.string = original;
    self.editedField = nil;
}
@end
