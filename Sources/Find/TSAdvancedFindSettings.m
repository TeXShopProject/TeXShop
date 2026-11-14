// SPDX-License-Identifier: GPL-2.0-or-later
#import <AppKit/AppKit.h>
#import "TSAdvancedFindSettings.h"

static NSString *const TSAdvancedFindOptionsKey = @"AdvancedFindOptions";
static NSString *const TSAdvancedFindInSelectionKey = @"AdvancedFindInSelection";
static NSString *const TSAdvancedFindWrapsKey = @"AdvancedFindWraps";
static NSString *const TSAdvancedFindClosesWhenDoneKey = @"AdvancedFindClosesWhenDone";
static NSString *const TSAdvancedFindLiveUpdateKey = @"AdvancedFindLiveUpdate";
static NSString *const TSAdvancedFindHistoryLimitKey = @"AdvancedFindHistoryLimit";
static NSString *const TSAdvancedFindHistoryKey = @"AdvancedFindHistory";
static NSString *const TSAdvancedFindReplaceHistoryKey = @"AdvancedFindReplaceHistory";

@interface TSAdvancedFindSettings ()
@property (nonatomic, readonly) NSUserDefaults *defaults;
@property (nonatomic, readonly, nullable) NSPasteboard *pasteboard;
@end

@implementation TSAdvancedFindSettings

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults findPasteboard:(nullable NSPasteboard *)pasteboard
{
    if ((self = [super init])) {
        _defaults = defaults;
        _pasteboard = pasteboard;
        _findString = @"";
        _replaceString = @"";
        [self reloadFindStringFromPasteboard];
    }
    return self;
}

- (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback
{
    id value = [self.defaults objectForKey:key];
    return value ? [self.defaults boolForKey:key] : fallback;
}

- (TSRegexFindOptions)options
{
    id value = [self.defaults objectForKey:TSAdvancedFindOptionsKey];
    return value ? (TSRegexFindOptions)[self.defaults integerForKey:TSAdvancedFindOptionsKey] : TSRegexFindDefaultOptions;
}

- (void)setOptions:(TSRegexFindOptions)options
{
    [self.defaults setInteger:(NSInteger)options forKey:TSAdvancedFindOptionsKey];
}

- (TSRegexReplacementSyntax)replacementSyntax
{
    return [self.defaults integerForKey:TSAdvancedFindReplacementSyntaxKey] == TSRegexReplacementSyntaxOgreKit ? TSRegexReplacementSyntaxOgreKit : TSRegexReplacementSyntaxICU;
}

- (void)setReplacementSyntax:(TSRegexReplacementSyntax)syntax { [self.defaults setInteger:syntax forKey:TSAdvancedFindReplacementSyntaxKey]; }
- (BOOL)inSelection { return [self boolForKey:TSAdvancedFindInSelectionKey fallback:NO]; }
- (void)setInSelection:(BOOL)inSelection { [self.defaults setBool:inSelection forKey:TSAdvancedFindInSelectionKey]; }
- (BOOL)wraps { return [self boolForKey:TSAdvancedFindWrapsKey fallback:YES]; }
- (void)setWraps:(BOOL)wraps { [self.defaults setBool:wraps forKey:TSAdvancedFindWrapsKey]; }
- (BOOL)closesWhenDone { return [self boolForKey:TSAdvancedFindClosesWhenDoneKey fallback:NO]; }
- (void)setClosesWhenDone:(BOOL)closesWhenDone { [self.defaults setBool:closesWhenDone forKey:TSAdvancedFindClosesWhenDoneKey]; }
- (BOOL)updatesResultsLive { return [self boolForKey:TSAdvancedFindLiveUpdateKey fallback:NO]; }
- (void)setUpdatesResultsLive:(BOOL)live { [self.defaults setBool:live forKey:TSAdvancedFindLiveUpdateKey]; }

- (NSUInteger)historyLimit
{
    NSInteger limit = [self.defaults objectForKey:TSAdvancedFindHistoryLimitKey] ? [self.defaults integerForKey:TSAdvancedFindHistoryLimitKey] : 20;
    return (NSUInteger)MAX(0, MIN(limit, 100));
}

- (NSArray<NSString *> *)historyForKey:(NSString *)key
{
    NSArray *stored = [self.defaults arrayForKey:key];
    NSMutableArray<NSString *> *history = [NSMutableArray array];
    for (id item in stored)
        if ([item isKindOfClass:[NSString class]])
            [history addObject:item];
    return history;
}

- (NSArray<NSString *> *)findHistory { return [self historyForKey:TSAdvancedFindHistoryKey]; }
- (NSArray<NSString *> *)replaceHistory { return [self historyForKey:TSAdvancedFindReplaceHistoryKey]; }

- (void)addString:(NSString *)string toHistoryForKey:(NSString *)key
{
    if (string.length == 0)
        return;
    NSMutableArray<NSString *> *history = [[self historyForKey:key] mutableCopy];
    [history removeObject:string];
    [history insertObject:string atIndex:0];
    while (history.count > self.historyLimit)
        [history removeLastObject];
    [self.defaults setObject:history forKey:key];
}

- (void)noteFindString { [self addString:self.findString toHistoryForKey:TSAdvancedFindHistoryKey]; }

- (void)noteReplaceString
{
    [self noteFindString];
    [self addString:self.replaceString toHistoryForKey:TSAdvancedFindReplaceHistoryKey];
}

- (void)clearHistories
{
    [self.defaults removeObjectForKey:TSAdvancedFindHistoryKey];
    [self.defaults removeObjectForKey:TSAdvancedFindReplaceHistoryKey];
}

- (void)clearFindHistory { [self.defaults removeObjectForKey:TSAdvancedFindHistoryKey]; }
- (void)clearReplaceHistory { [self.defaults removeObjectForKey:TSAdvancedFindReplaceHistoryKey]; }

- (void)setFindString:(NSString *)findString
{
    if ([findString isEqualToString:_findString])
        return;
    _findString = [findString copy];
    if (self.pasteboard && findString.length > 0) {
        [self.pasteboard clearContents];
        [self.pasteboard setString:findString forType:NSPasteboardTypeString];
    }
}

- (void)reloadFindStringFromPasteboard
{
    NSString *string = [self.pasteboard stringForType:NSPasteboardTypeString];
    if (string.length > 0)
        _findString = [string copy];
}

@end
