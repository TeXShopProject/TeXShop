// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsSearch.h"
@implementation TSSettingsSearchEntry
@synthesize category = _category, targetIdentifier = _targetIdentifier, text = _text, normalizedText = _normalizedText, weight = _weight, command = _command;
- (instancetype)initWithCategory:(TSSettingsCategoryID)category target:(NSString *)target text:(NSString *)text weight:(TSSettingsSearchWeight)weight command:(BOOL)command
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
- (NSString *)title
{
    for (TSSettingsSearchEntry *entry in self.entries)
        if (entry.command || entry.weight == TSSettingsSearchWeightLabel) return entry.text;
    // Descriptions and choices qualify a named setting; they are never its title.
    return @"";
}
- (NSString *)targetIdentifier { return self.entries.firstObject.targetIdentifier ?: @""; }
@end
@implementation TSSettingsSearch
@synthesize entries = _entries, categoryOrder = _categoryOrder;
- (instancetype)initWithBundle:(NSBundle *)bundle categoryOrder:(NSArray<TSSettingsCategoryID> *)order commandNames:(NSArray<NSString *> *)names
{
    self = [super init];
    if (self == nil) return nil;
    _categoryOrder = [order copy];
    NSMutableArray<TSSettingsSearchEntry *> *entries = [NSMutableArray array];
    void (^add)(TSSettingsCategoryID, NSString *, NSString *, NSString *, TSSettingsSearchWeight) = ^(TSSettingsCategoryID category, NSString *target, NSString *table, NSString *key, TSSettingsSearchWeight weight) {
        NSString *text = [bundle localizedStringForKey:key value:key table:table];
        if (text.length) [entries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:category target:target text:text weight:weight command:NO]];
    };
    // Only resource keys and category/control identifiers live in the map. The
    // localized text is read from the same tables used by the interface.
#include "TSSettingsSearchCatalog.inc"
    // Group headings qualify their own settings, rather than creating a result
    // that has no setting row. The catalog lists each heading before its rows.
    NSMutableDictionary<TSSettingsCategoryID, TSSettingsSearchEntry *> *headingsByCategory = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *seenRows = [NSMutableSet set];
    NSMutableArray<TSSettingsSearchEntry *> *rowEntries = [NSMutableArray array];
    for (TSSettingsSearchEntry *entry in entries) {
        if (entry.weight == TSSettingsSearchWeightHeading) { headingsByCategory[entry.category] = entry; continue; }
        [rowEntries addObject:entry];
        if (![seenRows containsObject:entry.targetIdentifier]) {
            [seenRows addObject:entry.targetIdentifier];
            TSSettingsSearchEntry *heading = headingsByCategory[entry.category];
            if (heading) [rowEntries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:entry.category target:entry.targetIdentifier text:heading.text weight:TSSettingsSearchWeightHeading command:NO]];
        }
    }
    [entries setArray:rowEntries];
    NSArray<NSString *> *dockTitles = @[@"Original", @"Classic Triangle", @"Retina Triangle", @"Classic Circle", @"Current (Default)"];
    NSArray<NSString *> *dockPeriods = @[@"Before 1.0", @"1.0–3.13", @"3.14–3.38", @"3.39–5.58", @"5.60–"];
    NSString *(^dockText)(NSString *) = ^(NSString *key) { return [bundle localizedStringForKey:key value:key table:@"SettingsDock"]; };
    for (NSUInteger i = 0; i < dockTitles.count; i++) {
        NSString *tip = [NSString stringWithFormat:@"%@ — %@", dockText(dockTitles[i]), dockText(dockPeriods[i])];
        [entries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:TSSettingsCategoryAppearance target:@"DockIconChoices" text:tip weight:TSSettingsSearchWeightDescription command:NO]];
    }
    for (NSString *category in order) add(category, @"", @"SettingsCategories", category, TSSettingsSearchWeightCategory);
    for (NSString *category in order) {
        add(category, @"category.description", @"SettingsCategories", [category stringByAppendingString:@".summary"], TSSettingsSearchWeightDescription);
    }
    for (NSString *name in names) if (name.length) {
        [entries addObject:[[TSSettingsSearchEntry alloc] initWithCategory:TSSettingsCategoryKeyboard target:@"shortcut.commands" text:name weight:TSSettingsSearchWeightCommand command:YES]];
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
        NSMutableDictionary<NSString *, NSMutableArray<TSSettingsSearchEntry *> *> *items = [NSMutableDictionary dictionary];
        NSMutableOrderedSet<NSString *> *order = [NSMutableOrderedSet orderedSet];
        NSMutableArray<TSSettingsSearchEntry *> *categoryText = [NSMutableArray array];
        for (TSSettingsSearchEntry *entry in self.entries) {
            if (![entry.category isEqualToString:category]) continue;
            if (!entry.targetIdentifier.length || [entry.targetIdentifier isEqualToString:@"category.description"]) { [categoryText addObject:entry]; continue; }
            // Commands share the table target but remain individually named results.
            NSString *key = entry.command ? [@"command:" stringByAppendingString:entry.text] : entry.targetIdentifier;
            if (items[key] == nil) { items[key] = [NSMutableArray array]; [order addObject:key]; }
            [items[key] addObject:entry];
        }
        for (NSString *key in order) {
            NSArray<TSSettingsSearchEntry *> *entries = items[key];
            NSInteger score = 0;
            for (NSString *token in tokens) {
                NSInteger best = 0;
                for (TSSettingsSearchEntry *entry in entries) {
                    NSRange range = [entry.normalizedText rangeOfString:token options:NSLiteralSearch];
                    if (range.location == NSNotFound) continue;
                    NSInteger bonus = entry.normalizedText.length == token.length ? TSSettingsSearchBonusExact : (range.location == 0 ? TSSettingsSearchBonusPrefix : TSSettingsSearchBonusSubstring);
                    best = MAX(best, entry.weight + bonus);
                }
                // Category text can find or qualify its settings. Tokens from
                // unrelated settings still cannot complete an AND query.
                for (TSSettingsSearchEntry *entry in categoryText) {
                    NSRange range = [entry.normalizedText rangeOfString:token options:NSLiteralSearch];
                    if (range.location == NSNotFound) continue;
                    NSInteger bonus = entry.normalizedText.length == token.length ? TSSettingsSearchBonusExact : (range.location == 0 ? TSSettingsSearchBonusPrefix : TSSettingsSearchBonusSubstring);
                    best = MAX(best, entry.weight + bonus);
                }
                if (!best) { score = 0; break; }
                score += best;
            }
            if (score) [results addObject:[[TSSettingsSearchResult alloc] initWithCategory:category entries:entries score:score]];
        }
    }
    [results sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(TSSettingsSearchResult *a, TSSettingsSearchResult *b) {
        if (a.score == b.score) return NSOrderedSame;
        return a.score > b.score ? NSOrderedAscending : NSOrderedDescending;
    }];
    return [results copy];
}
@end
