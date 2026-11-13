// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexReplacementRule.h"

// The keys of a CotEditor replacement definition.
static NSString *const TSRuleFindKey = @"findString";
static NSString *const TSRuleReplaceKey = @"replacementString";
static NSString *const TSRuleRegexKey = @"usesRegularExpression";
static NSString *const TSRuleIgnoresCaseKey = @"ignoresCase";
static NSString *const TSRuleEnabledKey = @"isEnabled";
static NSString *const TSRuleNoteKey = @"description";

/// YES for a JSON true or false; a number is not a boolean, as for Swift's JSONDecoder.
static BOOL TSIsBoolean(id value)
{
    return CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

@implementation TSRegexReplacementRule

- (instancetype)initWithFindString:(NSString *)findString replaceString:(NSString *)replaceString
             usesRegularExpression:(BOOL)usesRegularExpression ignoresCase:(BOOL)ignoresCase
                           enabled:(BOOL)enabled note:(nullable NSString *)note
{
    if ((self = [super init])) {
        _findString = [findString copy];
        _replaceString = [replaceString copy];
        _usesRegularExpression = usesRegularExpression;
        _ignoresCase = ignoresCase;
        _enabled = enabled;
        _note = [note copy];
    }
    return self;
}

- (nullable instancetype)initWithJSONObject:(NSDictionary<NSString *, id> *)object
{
    if (![object isKindOfClass:[NSDictionary class]])
        return nil;
    id find = object[TSRuleFindKey], replace = object[TSRuleReplaceKey];
    id regex = object[TSRuleRegexKey], ignoresCase = object[TSRuleIgnoresCaseKey], enabled = object[TSRuleEnabledKey];
    id note = object[TSRuleNoteKey];
    if (![find isKindOfClass:[NSString class]] || ![replace isKindOfClass:[NSString class]])
        return nil;
    // A null optional value counts as missing, as in Swift's decodeIfPresent.
    if (regex == (id)kCFNull) regex = nil;
    if (ignoresCase == (id)kCFNull) ignoresCase = nil;
    if (enabled == (id)kCFNull) enabled = nil;
    if (note == (id)kCFNull) note = nil;
    if ((regex && !TSIsBoolean(regex)) || (ignoresCase && !TSIsBoolean(ignoresCase)) || (enabled && !TSIsBoolean(enabled))
        || (note && ![note isKindOfClass:[NSString class]]))
        return nil;
    return [self initWithFindString:find
                      replaceString:replace
              usesRegularExpression:[regex boolValue]
                        ignoresCase:[ignoresCase boolValue]
                            enabled:enabled ? [enabled boolValue] : YES
                               note:note];
}

- (NSDictionary<NSString *, id> *)JSONObject
{
    NSMutableDictionary<NSString *, id> *object = [@{TSRuleFindKey: self.findString, TSRuleReplaceKey: self.replaceString} mutableCopy];
    if (self.usesRegularExpression)
        object[TSRuleRegexKey] = @YES;
    if (self.ignoresCase)
        object[TSRuleIgnoresCaseKey] = @YES;
    if (!self.enabled)
        object[TSRuleEnabledKey] = @NO;
    if (self.note)
        object[TSRuleNoteKey] = self.note;
    return object;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

static BOOL TSLiterallyEqual(NSString *_Nullable a, NSString *_Nullable b)
{
    if (!a || !b)
        return a == b;
    // Literal comparison: canonically equivalent strings can match differently.
    return [a compare:(NSString *_Nonnull)b options:NSLiteralSearch] == NSOrderedSame;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[TSRegexReplacementRule class]])
        return NO;
    TSRegexReplacementRule *other = object;
    return TSLiterallyEqual(other.findString, self.findString) && TSLiterallyEqual(other.replaceString, self.replaceString)
        && other.usesRegularExpression == self.usesRegularExpression && other.ignoresCase == self.ignoresCase
        && other.enabled == self.enabled && TSLiterallyEqual(other.note, self.note);
}

- (NSUInteger)hash
{
    return self.findString.hash ^ self.replaceString.hash;
}

@end
