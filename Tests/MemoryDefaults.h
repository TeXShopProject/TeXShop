#pragma once
#import <Cocoa/Cocoa.h>

// Test-only defaults: every value stays in memory, even if an assertion exits early.
@interface TSMemoryDefaults : NSUserDefaults
@property NSMutableDictionary *values;
@property NSMutableDictionary *fallbacks;
@property NSMutableDictionary<NSString *, NSDictionary *> *volatileValues;
@end
@implementation TSMemoryDefaults
- (instancetype)init { if ((self = [super init])) { _values = [NSMutableDictionary new]; _fallbacks = [NSMutableDictionary new]; _volatileValues = [NSMutableDictionary new]; } return self; }
- (id)objectForKey:(NSString *)key { return self.volatileValues[NSArgumentDomain][key] ?: self.values[key] ?: self.fallbacks[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { if (value) self.values[key] = value; else [self.values removeObjectForKey:key]; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
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
- (NSDictionary *)dictionaryRepresentation { NSMutableDictionary *result = [self.fallbacks mutableCopy]; [result addEntriesFromDictionary:self.values]; [result addEntriesFromDictionary:self.volatileValues[NSArgumentDomain] ?: @{}]; return result; }
- (void)setVolatileDomain:(NSDictionary *)domain forName:(NSString *)name { self.volatileValues[name] = [domain copy]; }
- (NSDictionary *)volatileDomainForName:(NSString *)name { return self.volatileValues[name] ?: @{}; }
- (void)removeVolatileDomainForName:(NSString *)name { [self.volatileValues removeObjectForKey:name]; }
- (NSArray *)volatileDomainNames { return self.volatileValues.allKeys; }
- (BOOL)synchronize { return YES; }
@end
