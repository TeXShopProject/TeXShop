#pragma once
#import <Cocoa/Cocoa.h>

// Test-only defaults: every value stays in memory, even if an assertion exits early.
@interface TSMemoryDefaults : NSUserDefaults
@property NSMutableDictionary *values;
@property NSMutableDictionary<NSString *, NSDictionary *> *persistentValues;
@property NSMutableDictionary *fallbacks;
@property NSMutableDictionary<NSString *, NSDictionary *> *volatileValues;
@end
@implementation TSMemoryDefaults
- (instancetype)init { if ((self = [super init])) { _persistentValues = [NSMutableDictionary new]; _values = [NSMutableDictionary new]; _fallbacks = [NSMutableDictionary new]; _volatileValues = [NSMutableDictionary new]; } return self; }
- (id)objectForKey:(NSString *)key { return self.volatileValues[NSArgumentDomain][key] ?: self.values[key] ?: self.persistentValues[[self applicationDomainName]][key] ?: self.fallbacks[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { if (value) self.values[key] = value; else [self removeObjectForKey:key]; }
- (void)removeObjectForKey:(NSString *)key {
    [self.values removeObjectForKey:key];
    NSString *name=[self applicationDomainName];
    NSMutableDictionary *domain=[self.persistentValues[name] mutableCopy];
    if(domain){[domain removeObjectForKey:key];self.persistentValues[name]=[domain copy];}
}
- (void)registerDefaults:(NSDictionary *)values { [self.fallbacks addEntriesFromDictionary:values]; }
- (NSInteger)integerForKey:(NSString *)key { return [[self objectForKey:key] integerValue]; }
- (BOOL)boolForKey:(NSString *)key { return [[self objectForKey:key] boolValue]; }
- (float)floatForKey:(NSString *)key { return [[self objectForKey:key] floatValue]; }
- (double)doubleForKey:(NSString *)key { return [[self objectForKey:key] doubleValue]; }
- (NSString *)stringForKey:(NSString *)key { id v = [self objectForKey:key]; return [v isKindOfClass:NSString.class] ? v : [v isKindOfClass:NSNumber.class] ? [v stringValue] : nil; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setFloat:(float)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (NSArray *)arrayForKey:(NSString *)key { id value = [self objectForKey:key]; return [value isKindOfClass:NSArray.class] ? value : nil; }
- (NSDictionary *)dictionaryForKey:(NSString *)key { id value = [self objectForKey:key]; return [value isKindOfClass:NSDictionary.class] ? value : nil; }
- (NSData *)dataForKey:(NSString *)key { id value = [self objectForKey:key]; return [value isKindOfClass:NSData.class] ? value : nil; }
- (NSDictionary *)dictionaryRepresentation { NSMutableDictionary *result = [self.fallbacks mutableCopy]; [result addEntriesFromDictionary:self.persistentValues[[self applicationDomainName]] ?: @{}]; [result addEntriesFromDictionary:self.values]; [result addEntriesFromDictionary:self.volatileValues[NSArgumentDomain] ?: @{}]; return result; }
- (void)setVolatileDomain:(NSDictionary *)domain forName:(NSString *)name { self.volatileValues[name] = [domain copy]; }
- (NSDictionary *)volatileDomainForName:(NSString *)name { return self.volatileValues[name] ?: @{}; }
- (void)removeVolatileDomainForName:(NSString *)name { [self.volatileValues removeObjectForKey:name]; }
- (NSArray *)volatileDomainNames { return self.volatileValues.allKeys; }
- (NSString *)applicationDomainName { return NSBundle.mainBundle.bundleIdentifier ?: @"TeXShop"; }
- (void)setPersistentDomain:(NSDictionary *)domain forName:(NSString *)name {
    // Copy property-list values so subsequent caller mutations cannot affect the domain.
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:domain format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!data) [NSException raise:NSInvalidArgumentException format:@"Invalid in-memory defaults domain"];
    self.persistentValues[name] = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    if ([name isEqual:[self applicationDomainName]]) [self.values removeAllObjects];
}
- (void)removePersistentDomainForName:(NSString *)name {
    [self.persistentValues removeObjectForKey:name];
    if ([name isEqual:[self applicationDomainName]]) [self.values removeAllObjects];
}
- (NSDictionary *)persistentDomainForName:(NSString *)name {
    if (![name isEqual:[self applicationDomainName]]) return self.persistentValues[name];
    if (!self.persistentValues[name] && !self.values.count) return nil;
    NSMutableDictionary *domain = [self.persistentValues[name] mutableCopy] ?: [NSMutableDictionary new];
    [domain addEntriesFromDictionary:self.values]; return [domain copy];
}
- (NSArray *)persistentDomainNames { return self.persistentValues.allKeys; }
- (BOOL)synchronize { return YES; }
@end
