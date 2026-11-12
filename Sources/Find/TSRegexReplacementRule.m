// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexReplacementRule.h"

static NSString *const TSRuleFindField = @"find";
static NSString *const TSRuleReplaceField = @"replace";
static NSString *const TSRuleOptionsField = @"options";
static NSString *const TSRuleSyntaxField = @"syntax";
static NSString *const TSRuleEnabledField = @"enabled";
static NSString *const TSRuleNoteField = @"note";

@implementation TSRegexReplacementRule

- (instancetype)initWithFindString:(NSString *)findString replaceString:(NSString *)replaceString options:(TSRegexFindOptions)options replacementSyntax:(TSRegexReplacementSyntax)replacementSyntax enabled:(BOOL)enabled note:(NSString *)note
{
    if ((self = [super init])) {
        _findString = [findString copy];
        _replaceString = [replaceString copy];
        _options = options;
        _replacementSyntax = replacementSyntax == TSRegexReplacementSyntaxOgreKit ? TSRegexReplacementSyntaxOgreKit : TSRegexReplacementSyntaxICU;
        _enabled = enabled;
        _note = [note copy];
    }
    return self;
}

- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary
{
    id find = dictionary[TSRuleFindField], replace = dictionary[TSRuleReplaceField], options = dictionary[TSRuleOptionsField];
    id enabled = dictionary[TSRuleEnabledField], note = dictionary[TSRuleNoteField], syntax = dictionary[TSRuleSyntaxField];
    if (![find isKindOfClass:[NSString class]])
        return nil;
    return [self initWithFindString:find
                      replaceString:[replace isKindOfClass:[NSString class]] ? replace : @""
                            options:[options isKindOfClass:[NSNumber class]] ? (TSRegexFindOptions)[options unsignedIntegerValue] : TSRegexFindDefaultOptions
                  replacementSyntax:[syntax isKindOfClass:[NSNumber class]] ? (TSRegexReplacementSyntax)[syntax integerValue] : TSRegexReplacementSyntaxICU
                            enabled:[enabled isKindOfClass:[NSNumber class]] ? [enabled boolValue] : YES
                               note:[note isKindOfClass:[NSString class]] ? note : @""];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation
{
    return @{TSRuleFindField: self.findString, TSRuleReplaceField: self.replaceString, TSRuleOptionsField: @(self.options),
             TSRuleSyntaxField: @(self.replacementSyntax),
             TSRuleEnabledField: @(self.enabled), TSRuleNoteField: self.note};
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)object
{
    return [object isKindOfClass:[TSRegexReplacementRule class]] && [[object dictionaryRepresentation] isEqual:self.dictionaryRepresentation];
}

- (NSUInteger)hash
{
    return self.findString.hash ^ self.replaceString.hash;
}

@end
