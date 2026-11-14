// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceInput.h"
#import "TSSourceFormatRanges.h"
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

NSString *TSPreferenceRegisteredText(NSUserDefaults *defaults, TSPreferenceKey key)
{
    id value = [defaults volatileDomainForName:NSRegistrationDomain][key];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

NSString *TSPreferenceTextBesideDefault(NSUserDefaults *defaults, TSPreferenceKey key)
{
    NSString *value = [defaults stringForKey:key];
    if (value == nil || [value isEqualToString:TSPreferenceRegisteredText(defaults, key) ?: @""]) return @"";
    return value;
}

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
- (instancetype)initRestoringDefaultForKey:(TSPreferenceKey)key
{
    self = [self initWithKey:key kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil];
    if (self != nil) _restoresDefaultWhenEmpty = YES;
    return self;
}
- (BOOL)storeValue:(TSPreferenceInputValue *)value inDefaults:(NSUserDefaults *)defaults
{
    NSString *text = value.textValue;
    if (!self.restoresDefaultWhenEmpty || (text.length > 0 && ![text isEqualToString:TSPreferenceRegisteredText(defaults, self.key) ?: @""]))
        return [value storeInDefaults:defaults forKey:self.key];
    id before = [defaults objectForKey:self.key];
    [defaults removeObjectForKey:self.key];
    id after = [defaults objectForKey:self.key];
    return !(before == after || [before isEqual:after]);
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
    // A whole number is shown as the source windows apply it: inside the range
    // and without a fraction. The stored value itself is left as it is.
    if (self.restoresDefaultWhenEmpty) return TSPreferenceTextBesideDefault(defaults, self.key);
    if (self.kind == TSPreferenceInputText) return [defaults stringForKey:self.key] ?: @"";
    NSObject *stored = [defaults objectForKey:self.key];
    NSNumber *number = [stored isKindOfClass:NSNumber.class] ? (NSNumber *)stored : nil;
    if (number != nil && self.kind == TSPreferenceInputInteger)
        number = @(TSIntegerInRange(number.doubleValue, (TSIntegerRange){(NSInteger)self.minimum, (NSInteger)self.maximum}));
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

@implementation TSIntegerInputFormatter
- (instancetype)initWithInput:(TSPreferenceInput *)input
{
    self = [super init];
    if (self == nil) return nil;
    self.numberStyle = NSNumberFormatterNoStyle;
    self.allowsFloats = NO;
    self.minimum = @(input.minimum);
    self.maximum = @(input.maximum);
    return self;
}
- (nullable NSString *)stringForObjectValue:(nullable id)value
{
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [NSString stringWithFormat:@"%ld", (long)[value integerValue]];
    return nil;
}
- (BOOL)getObjectValue:(out id _Nullable *)value forString:(NSString *)string range:(inout nullable NSRange *)range error:(out NSError **)error
{
    if (value != NULL) *value = [string copy];
    return YES;
}
- (BOOL)getObjectValue:(out id _Nullable *)value forString:(NSString *)string errorDescription:(out NSString * _Nullable *)error
{
    if (value != NULL) *value = [string copy];
    return YES;
}
- (BOOL)isPartialStringValid:(NSString * _Nonnull *)partial proposedSelectedRange:(NSRangePointer)selection
              originalString:(NSString *)original originalSelectedRange:(NSRange)originalSelection
            errorDescription:(NSString * _Nullable *)error
{
    // Refuse the whole edit rather than dropping characters from it: removing
    // the separator from a pasted 1.5 would silently turn it into 15.
    NSString *digits = [*partial precomposedStringWithCompatibilityMapping];
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
    if ([digits rangeOfCharacterFromSet:other].location != NSNotFound) return NO;
    if (![digits isEqualToString:*partial]) {
        *partial = digits;
        if (selection != NULL) *selection = NSMakeRange(digits.length, 0);
        return NO;
    }
    return YES;
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
    BOOL changed = [rule storeValue:value inDefaults:defaults];
    field.stringValue = rule.restoresDefaultWhenEmpty ? [rule displayStringFromDefaults:defaults] : [rule displayStringForValue:value];
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
