// When ~/Library/TeXShop is refreshed from the application: once per display version, never per build.
// Everything happens in a temporary folder; the real ~/Library/TeXShop is not touched.
#import <Foundation/Foundation.h>
#import "TSLibraryVersion.h"

static int failures;
static void Check(BOOL condition, NSString *message) { if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }

static void Write(NSString *folder, NSString *text)
{
    [text writeToFile:[folder stringByAppendingPathComponent:@".Version"] atomically:YES encoding:NSASCIIStringEncoding error:NULL];
}

// One launch: refresh when needed and remember the version, as TSAppDelegate does.
static BOOL Launch(NSString *folder, NSString *applicationVersion)
{
    BOOL needs = TSLibraryNeedsUpdating(TSLibraryVersionInFolder(folder), applicationVersion);
    if (needs)
        Check(TSLibraryRecordVersion(folder, applicationVersion), @"The version can be written");
    return needs;
}

int main(void)
{
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TeXShop-LibraryVersion-%d", getpid()]];
        NSString *folder = [base stringByAppendingPathComponent:@"New"];
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];

        Check(TSLibraryVersionInFolder(folder) == nil, @"No .Version reads as nothing");
        Check(Launch(folder, @"6.00 beta-1"), @"Without a .Version the files are copied");
        Check([TSLibraryVersionInFolder(folder) isEqual:@"6.00 beta-1"], @"The display version is remembered");
        NSString *written = [NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:@".Version"] encoding:NSASCIIStringEncoding error:NULL];
        Check([written isEqual:@"6.00 beta-1\n"], @".Version holds the display version and a newline, like the earlier files");
        Check(written.doubleValue == 6.0, @"Earlier versions read what is written as the number 6.0");
        Check(!Launch(folder, @"6.00 beta-1"), @"The next launch of the same version copies nothing");

        // 5.59 and the 5.60 betas shipped New/.Version with 5.59 in it.
        Write(folder, @"5.59\n");
        Check(Launch(folder, @"6.00 beta-1"), @"Coming from 5.59 or a 5.60 beta, 6.00 beta-1 copies once");
        Check(!Launch(folder, @"6.00 beta-1"), @"... and only once");
        Write(folder, @"5.6");
        Check(Launch(folder, @"6.00 beta-1"), @"Coming from a .Version of 5.6, it copies once");
        Check(!Launch(folder, @"6.00 beta-1"), @"... and only once");

        Check(Launch(folder, @"6.00 beta-2"), @"The next beta of the same number copies");
        Check(Launch(folder, @"6.00"), @"The release after its betas copies");
        Check(!Launch(folder, @"6.00"), @"... once");
        Check(Launch(folder, @"6.01"), @"A later version copies");
        Check(!Launch(folder, @"6.00"), @"An earlier number does not copy over a later one");
        Check([TSLibraryVersionInFolder(folder) isEqual:@"6.01"], @"... and leaves the later version in .Version");

        Write(folder, @"5.59\n");
        Check(!Launch(folder, @"5.59"), @"5.59 over its own files copies nothing");
        Check(!TSLibraryNeedsUpdating(@"6.00 beta-1", @"5.59"), @"5.59 after 6.00 beta-1 copies nothing");
        Check(!TSLibraryNeedsUpdating(@"6.00 beta-1", nil), @"Without a display version nothing is copied");
        Check(TSLibraryNeedsUpdating(@"garbage", @"6.00 beta-1"), @"An unreadable .Version copies");

        [fm removeItemAtPath:base error:NULL];
    }
    if (failures) { fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    puts("PASS library version");
    return 0;
}
