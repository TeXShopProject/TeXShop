// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsSearch.h"
@implementation TSSettingsSearchEntry
@synthesize category = _category, targetIdentifier = _targetIdentifier, text = _text, normalizedText = _normalizedText, weight = _weight, command = _command;
- (instancetype)initWithCategory:(TSSettingsCategoryID)category target:(NSString *)target text:(NSString *)text weight:(NSInteger)weight command:(BOOL)command
{
    self = [super init];
    if (self == nil) return nil;
    _category = [category copy]; _targetIdentifier = [target copy]; _text = [text copy];
    _normalizedText = TSSettingsNormalizedText(text); _weight = weight; _command = command;
    return self;
}
@end
@implementation TSSettingsSearchResult
@synthesize category = _category, entries = _entries, score = _score;
- (instancetype)initWithCategory:(TSSettingsCategoryID)category entries:(NSArray<TSSettingsSearchEntry *> *)entries score:(NSInteger)score
{
    self = [super init];
    if (self == nil) return nil;
    _category = [category copy]; _entries = [entries copy]; _score = score;
    return self;
}
@end
@implementation TSSettingsSearch
@synthesize entries = _entries, categoryOrder = _categoryOrder;
- (instancetype)initWithBundle:(NSBundle *)bundle categoryOrder:(NSArray<TSSettingsCategoryID> *)order commandNames:(NSArray<NSString *> *)names
{
    self = [super init];
    if (self == nil) return nil;
    _categoryOrder = [order copy];
    NSMutableArray<TSSettingsSearchEntry *> *entries = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSString *, NSString *, NSInteger) = ^(NSString *category, NSString *target, NSString *table, NSString *key, NSInteger weight) {
        NSString *text = [bundle localizedStringForKey:key value:key table:table];
        if (text.length) [entries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:category target:target text:text weight:weight command:NO]];
    };
    // Only resource keys and category/control identifiers live in the map. The
    // localized text is read from the same tables used by the interface.
#include "TSSettingsSearchCatalog.inc"
    NSString *bindings = [NSString stringWithFormat:@"%@ — %@", [bundle localizedStringForKey:@"Key Bindings" value:@"Key Bindings" table:@"Localizable"], [bundle localizedStringForKey:@"Defaults for New Documents" value:@"Defaults for New Documents" table:@"Localizable"]];
    [entries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:TSSettingsCategoryKeyboard target:@"heading.group.bindings" text:bindings weight:60 command:NO]];
    for (NSString *category in order) add(category, @"", @"SettingsCategories", category, 100);
    for (NSString *category in order) {
        NSMutableOrderedSet<NSString *> *headings = [NSMutableOrderedSet orderedSet];
        for (TSSettingsSearchEntry *entry in entries) if ([entry.category isEqual:category] && entry.weight == 60 && headings.count < 3) [headings addObject:entry.text];
        if (headings.count) [entries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:category target:@"category.description" text:[headings.array componentsJoinedByString:@" · "] weight:20 command:NO]];
    }
    for (NSString *name in names) if (name.length) {
        [entries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:TSSettingsCategoryKeyboard target:@"shortcut.commands" text:name weight:10 command:YES]];
    }
    _entries = [entries copy];
    return self;
}
- (NSString *)categoryDescription:(TSSettingsCategoryID)category
{
    for (TSSettingsSearchEntry *entry in self.entries) if ([entry.category isEqual:category] && [entry.targetIdentifier isEqual:@"category.description"]) return entry.text;
    return @"";
}
- (NSArray<TSSettingsSearchResult *> *)resultsForQuery:(NSString *)query
{
    NSArray<NSString *> *tokens = TSSettingsQueryTokens(query);
    if (!tokens.count) return @[];
    NSMutableArray<TSSettingsSearchResult *> *results = [NSMutableArray array];
    for (TSSettingsCategoryID category in self.categoryOrder) {
        NSMutableOrderedSet<TSSettingsSearchEntry *> *matched = [NSMutableOrderedSet orderedSet];
        NSInteger score = 0;
        for (NSString *token in tokens) {
            NSInteger best = 0;
            for (TSSettingsSearchEntry *entry in self.entries) {
                if (![entry.category isEqualToString:category]) continue;
                NSRange range = [entry.normalizedText rangeOfString:token];
                if (range.location == NSNotFound) continue;
                NSInteger bonus = entry.normalizedText.length == token.length ? 20 : (range.location == 0 ? 10 : 0);
                best = MAX(best, entry.weight + bonus); [matched addObject:entry];
            }
            if (!best) { score = 0; break; }
            score += best;
        }
        if (score) [results addObject:[[TSSettingsSearchResult alloc] initWithCategory:category entries:matched.array score:score]];
    }
    [results sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(TSSettingsSearchResult *a, TSSettingsSearchResult *b) {
        if (a.score == b.score) return NSOrderedSame;
        return a.score > b.score ? NSOrderedAscending : NSOrderedDescending;
    }];
    return [results copy];
}
@end
