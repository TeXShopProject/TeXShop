// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindMatchCache.h"
#import <objc/runtime.h>

static const void *TSMatchCacheKey = &TSMatchCacheKey;
static const NSUInteger TSMatchCacheSize = 4;

@interface TSAdvancedFindMatchCache ()
@property (nonatomic, readwrite) NSUInteger version;
@property (nonatomic, readwrite) NSUInteger hits;
@property (nonatomic, readonly) NSMutableArray<NSString *> *keys; // oldest first
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSArray<NSValue *> *> *entries;
@end

@implementation TSAdvancedFindMatchCache

+ (instancetype)cacheForTextStorage:(NSTextStorage *)storage
{
    TSAdvancedFindMatchCache *cache = objc_getAssociatedObject(storage, TSMatchCacheKey);
    if (!cache) {
        cache = [[TSAdvancedFindMatchCache alloc] initWithTextStorage:storage];
        objc_setAssociatedObject(storage, TSMatchCacheKey, cache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cache;
}

- (instancetype)initWithTextStorage:(NSTextStorage *)storage
{
    if ((self = [super init])) {
        _keys = [NSMutableArray array];
        _entries = [NSMutableDictionary dictionary];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textStorageDidProcessEditing:)
                                                   name:NSTextStorageDidProcessEditingNotification object:storage];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)textStorageDidProcessEditing:(NSNotification *)notification
{
    NSTextStorage *storage = notification.object;
    if (!(storage.editedMask & NSTextStorageEditedCharacters))
        return; // a color or a font does not move any match
    self.version++;
    [self.keys removeAllObjects];
    [self.entries removeAllObjects];
}

- (nullable NSArray<NSValue *> *)matchesForKey:(NSString *)key
{
    NSArray<NSValue *> *matches = self.entries[key];
    if (matches)
        self.hits++;
    return matches;
}

- (void)setMatches:(NSArray<NSValue *> *)matches forKey:(NSString *)key
{
    [self.keys removeObject:key];
    [self.keys addObject:key];
    self.entries[key] = [matches copy];
    while (self.keys.count > TSMatchCacheSize) {
        [self.entries removeObjectForKey:(NSString *_Nonnull)self.keys.firstObject];
        [self.keys removeObjectAtIndex:0];
    }
}

@end
