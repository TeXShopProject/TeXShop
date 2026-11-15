// How the bundled Sparkle orders build numbers (the commit count) against the earlier build versions.
// sparkle:version in the feed and CFBundleVersion of the application are compared this way.
#import <Foundation/Foundation.h>
#import <Sparkle/SUStandardVersionComparator.h>

static int failures;

static void Expect(NSString *a, NSComparisonResult expected, NSString *b, NSString *why)
{
    NSComparisonResult result = [[SUStandardVersionComparator defaultComparator] compareVersion:a toVersion:b];
    const char *names[] = {"<", "=", ">"};
    if (result != expected) {
        failures++;
        fprintf(stderr, "FAIL: %s %s %s expected, got %s (%s)\n", a.UTF8String, names[expected + 1], b.UTF8String, names[result + 1], why.UTF8String);
    } else {
        printf("ok: %s %s %s\n", a.UTF8String, names[expected + 1], b.UTF8String);
    }
}

int main(void)
{
    @autoreleasepool {
        Expect(@"5.59", NSOrderedAscending, @"1512", @"5.59 users are offered 6.00 beta-1");
        Expect(@"5.60b10", NSOrderedAscending, @"1512", @"5.60 beta-10 users are offered 6.00 beta-1");
        Expect(@"6.00b1", NSOrderedAscending, @"1512", @"trial builds of 6.00 beta-1 are offered the beta");
        Expect(@"1512", NSOrderedAscending, @"1513", @"a later commit is a later build");
        Expect(@"1512", NSOrderedDescending, @"5.59", @"6.00 beta-1 does not take 5.59 for a newer version");
        Expect(@"1512", NSOrderedDescending, @"5.60b10", @"6.00 beta-1 does not take 5.60 beta-10 for a newer version");
        Expect(@"1512", NSOrderedSame, @"1512", @"the same build is up to date");
        Expect(@"999", NSOrderedAscending, @"1000", @"numbers, not strings, are compared");
    }
    if (failures) { fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    puts("PASS Sparkle version order");
    return 0;
}
