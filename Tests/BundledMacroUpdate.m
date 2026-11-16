// Calls TSUpdateUnchangedBundledMacros(user, bundled) and prints the number of macros updated.
#import <Foundation/Foundation.h>
#import "TSBundledMacroUpdate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 3)
            return 2;
        printf("%lu\n", (unsigned long)TSUpdateUnchangedBundledMacros(@(argv[1]), @(argv[2])));
    }
    return 0;
}
