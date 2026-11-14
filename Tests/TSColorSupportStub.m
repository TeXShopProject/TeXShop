// SPDX-License-Identifier: GPL-2.0-or-later
// For the tests that compile the shared syntax coloring's color scheme (Sources/Syntax/TSSyntaxColorScheme.m) without
// the application: the theme look-ups of TSColorSupport, which those tests never reach, answer nothing.
#import "TSColorSupport.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation TSColorSupport
+ (id)sharedInstance
{
    static TSColorSupport *shared;
    if (!shared)
        shared = [TSColorSupport new];
    return shared;
}
- (NSColor *)colorFromDictionary:(NSDictionary *)theDictionary andKey:(NSString *)theKey
{
    return nil;
}
@end
