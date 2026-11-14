// The prerelease channel switch: forced on at the first launch of each prerelease build.
// The defaults object keeps its values in memory; nothing reaches the user's defaults.
#import <Cocoa/Cocoa.h>
#import "TSSparkleController.h"
#import "globals.h"

@interface TSMemoryDefaults : NSUserDefaults
@property (strong) NSMutableDictionary *values;
@property (strong) NSMutableDictionary *registered;
@end
@implementation TSMemoryDefaults
- (instancetype)init { self = [super initWithSuiteName:@"TeXShop.PrereleaseUpdatesTest.unused"]; _values = [NSMutableDictionary dictionary]; _registered = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key] ?: self.registered[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { if (value) self.values[key] = value; else [self.values removeObjectForKey:key]; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
- (void)registerDefaults:(NSDictionary<NSString *,id> *)dictionary { [self.registered addEntriesFromDictionary:dictionary]; }
- (BOOL)boolForKey:(NSString *)key { return [[self objectForKey:key] boolValue]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (NSString *)stringForKey:(NSString *)key { id v = [self objectForKey:key]; return [v isKindOfClass:NSString.class] ? v : nil; }
@end

static int failures;
static void Check(BOOL condition, NSString *message) { if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
static BOOL Allows(NSUserDefaults *d) { return [[TSSparkleController allowedChannelsWithDefaults:d] isEqual:[NSSet setWithObject:TSSparklePrereleaseChannel]]; }
static void Launch(NSUserDefaults *d, NSString *version) { [TSSparkleController preparePrereleaseDefaultsForVersion:version defaults:d]; }

int main(void)
{
    @autoreleasepool {
        Check([TSSparklePrereleaseChannel isEqual:@"prerelease"], @"The appcast channel is named prerelease");
        Check([TSSparkleController isPrereleaseVersion:@"5.60b10"], @"5.60b10 is a prerelease");
        Check([TSSparkleController isPrereleaseVersion:@"5.61a1"], @"5.61a1 is a prerelease");
        Check(![TSSparkleController isPrereleaseVersion:@"5.60"], @"5.60 is a release");
        Check(![TSSparkleController isPrereleaseVersion:@"5.60.1"], @"5.60.1 is a release");
        Check(![TSSparkleController isPrereleaseVersion:nil], @"No version is a release");

        TSMemoryDefaults *release = [TSMemoryDefaults new];
        Launch(release, @"5.60");
        Check(![release boolForKey:SparklePrereleaseUpdatesKey] && !Allows(release), @"A release starts with prereleases off");
        Check(release.values.count == 0, @"A release launch writes nothing");
        Check([[TSSparkleController allowedChannelsWithDefaults:release] count] == 0, @"Off allows only the default channel");

        TSMemoryDefaults *beta = [TSMemoryDefaults new];
        Launch(beta, @"5.60b11");
        Check([beta.values[SparklePrereleaseUpdatesKey] boolValue] && Allows(beta), @"The first launch of a prerelease turns prereleases on");
        [beta setBool:NO forKey:SparklePrereleaseUpdatesKey];
        Launch(beta, @"5.60b11");
        Check(![beta boolForKey:SparklePrereleaseUpdatesKey] && !Allows(beta), @"Turned off, it stays off on later launches of the same prerelease");
        Launch(beta, @"5.60b12");
        Check([beta boolForKey:SparklePrereleaseUpdatesKey] && Allows(beta), @"The first launch of the next prerelease turns it on again");
        Launch(beta, @"5.60");
        Check([beta boolForKey:SparklePrereleaseUpdatesKey], @"A release does not turn it off");
        [beta setBool:NO forKey:SparklePrereleaseUpdatesKey];
        Launch(beta, @"5.60");
        Check(![beta boolForKey:SparklePrereleaseUpdatesKey], @"A release does not turn it on");

        TSMemoryDefaults *earlier = [TSMemoryDefaults new];
        [earlier setBool:NO forKey:SparklePrereleaseUpdatesKey];
        Launch(earlier, @"5.60b11");
        Check([earlier boolForKey:SparklePrereleaseUpdatesKey], @"A value from before this prerelease is overridden on its first launch");
    }
    if (failures) { fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    puts("PASS prerelease updates");
    return 0;
}
